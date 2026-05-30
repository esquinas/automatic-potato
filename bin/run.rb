#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "date"
require "yaml"

TELEGRAM_MAX_MSG_CHARS = 3800
WEEK_DAYS              = 7
TMDB_AMBIGUITY_RATIO   = 2.0

CINEMAS = YAML.load_file(File.join(__dir__, "..", "config", "cinemas.yml"))["cinemas"].freeze

# ---------------------------------------------------------------------------
# Domain objects
# ---------------------------------------------------------------------------

class Film
  attr_accessor :title, :localized_title, :year

  def initialize(localized_title:, year:, title: nil)
    @title           = title
    @localized_title = localized_title
    @year            = year
  end

  def ==(other)
    other.is_a?(Film) && localized_title == other.localized_title && year == other.year
  end

  alias eql? ==

  def hash
    [localized_title, year].hash
  end
end

ScreeningSession = Data.define(:film, :date, :starts_at, :original_version?)

Rating = Data.define(:score) do
  NULL = new(score: nil).freeze

  def self.null = NULL
  def present?  = !score.nil?
  def formatted = score && format("★ %.1f", score)
end

# ---------------------------------------------------------------------------
# Shared HTTP
# ---------------------------------------------------------------------------

module HttpClient
  def http_get(url, headers = {}, retried: false)
    sleep(1.5 + rand)
    uri  = URI(url)
    req  = Net::HTTP::Get.new(uri, headers)
    resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 10) { |h| h.request(req) }
    return resp if resp.code == "200" || retried

    puts "Retrying #{url}"
    http_get(url, headers, retried: true)
  end
end

# ---------------------------------------------------------------------------
# SensacineAdapter
# ---------------------------------------------------------------------------

class SensacineAdapter
  include HttpClient

  VO_BUCKETS         = %w[original local].freeze
  UNFILTERED_BUCKETS = %w[original local dubbed].freeze

  HEADERS = {
    "User-Agent"      => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Accept"          => "application/json",
    "Accept-Language" => "es-ES,es;q=0.9",
    "Referer"         => "https://www.sensacine.com/cines/cine/"
  }.freeze

  def fetch_theater_movie_sessions(date:, theater_id:)
    url = "https://www.sensacine.com/_/showtimes/theater-#{theater_id}/d-#{date}/p-1/"

    puts "GET #{url}"
    resp = http_get(url, HEADERS)
    puts "HTTP #{resp.code}"
    return [] unless resp.code == "200"

    parse_sessions(JSON.parse(resp.body)["results"] || [], date)
  end

  private

  def parse_sessions(results, date)
    results.flat_map do |entry|
      film = Film.new(
        localized_title: entry.dig("movie", "title") || "(untitled)",
        year:            entry.dig("movie", "release", "year")
      )

      UNFILTERED_BUCKETS.flat_map do |bucket|
        original_version = VO_BUCKETS.include?(bucket)

        (entry.dig("showtimes", bucket) || []).filter_map do |showtime|
          starts_at = showtime["startsAt"]&.slice(11, 5)
          next unless starts_at

          ScreeningSession.new(
            film:              film,
            date:              date,
            starts_at:         starts_at,
            original_version?: original_version
          )
        end
      end
    end
  end
end

# ---------------------------------------------------------------------------
# TmdbAdapter
# ---------------------------------------------------------------------------

class TmdbAdapter
  include HttpClient

  def initialize(api_key:)
    @api_key = api_key
  end

  def fetch_original_title(film)
    search(film.localized_title, film.year)&.first&.dig("original_title")
  end

  def rating_for(film)
    results = search(film.title || film.localized_title, film.year)
    return Rating.null if results.nil? || results.empty?

    top    = results[0]
    second = results[1]

    return Rating.null if top["vote_count"].to_i.zero?

    top_score    = top["vote_average"].to_f
    second_score = (second&.dig("vote_average") || 0).to_f
    return Rating.null if second_score > 0 && top_score / second_score < TMDB_AMBIGUITY_RATIO

    Rating.new(score: top_score)
  end

  private

  def search(title, year = nil)
    query = URI.encode_www_form(query: title, language: "es-ES", api_key: @api_key)
    query += "&year=#{year}" if year
    resp = http_get("https://api.themoviedb.org/3/search/movie?#{query}")
    return nil unless resp.code == "200"

    JSON.parse(resp.body)["results"] || []
  end
end

# ---------------------------------------------------------------------------
# TelegramAdapter
# ---------------------------------------------------------------------------

class TelegramAdapter
  def initialize(token:, chat_id:)
    @token   = token
    @chat_id = chat_id
  end

  def send_message(text)
    uri = URI("https://api.telegram.org/bot#{@token}/sendMessage")
    req = Net::HTTP::Post.new(uri)
    req.content_type = "application/json"
    req.body = JSON.generate(chat_id: @chat_id, text: text, parse_mode: "HTML")
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  end
end

# ---------------------------------------------------------------------------
# WeeklyNotifier
# ---------------------------------------------------------------------------

class WeeklyNotifier
  def initialize(sensacine:, tmdb:, telegram:, cinemas:)
    @sensacine = sensacine
    @tmdb      = tmdb
    @telegram  = telegram
    @cinemas   = cinemas
  end

  def run(today: Date.today)
    lines         = []
    no_vo_cinemas = []

    @cinemas.each do |cinema|
      sessions = collect_sessions(cinema, today)

      if sessions.empty?
        no_vo_cinemas << cinema["name"]
        next
      end

      lines.concat(render_cinema(cinema, sessions, today))
      lines << ""
    end

    unless no_vo_cinemas.empty?
      lines << "The following venues had no VO sessions: #{no_vo_cinemas.join(", ")}"
      lines << ""
    end

    message = lines.join("\n").strip
    message = "#{message[0, TELEGRAM_MAX_MSG_CHARS]}\n... (truncated)" if message.length > TELEGRAM_MAX_MSG_CHARS

    @telegram.send_message(message)
    puts "Sent #{message.length} chars to Telegram"
  end

  private

  def collect_sessions(cinema, today)
    WEEK_DAYS.times.flat_map do |offset|
      date     = (today + offset).to_s
      sessions = @sensacine.fetch_theater_movie_sessions(date: date, theater_id: cinema["id"])
      cinema["check_vo"] ? sessions.select(&:original_version?) : sessions
    end
  end

  def render_cinema(cinema, sessions, today)
    week_end     = (today + WEEK_DAYS - 1).to_s
    unique_films = sessions.map(&:film).uniq

    unique_films.each { |film| film.title = @tmdb.fetch_original_title(film) }

    film_lines = unique_films.flat_map do |film|
      render_film(film, @tmdb.rating_for(film), sessions.select { |s| s.film == film })
    end

    [cinema_header(cinema, "#{cinema["name"]} — #{today} → #{week_end}"), *film_lines]
  end

  def render_film(film, rating, sessions)
    title_line = "<b>#{film.localized_title}</b>"
    title_line += " <i>(#{film.title})</i>" if film.title && film.title.downcase != film.localized_title.downcase
    title_line += " #{rating.formatted}"    if rating.present?

    dates_map = sessions
      .group_by(&:date)
      .transform_values { |ss| ss.map(&:starts_at).sort.uniq }
      .sort.to_h

    showtime_lines = if dates_map.keys.length == WEEK_DAYS
      all_times = dates_map.values.flatten.sort.uniq
      ["  All week: #{dates_map.keys.min} → #{dates_map.keys.max}: #{all_times.join(", ")}"]
    else
      dates_map.map { |date, times| "  #{format_date(date)}: #{times.join(", ")}" }
    end

    ["", title_line, *showtime_lines]
  end

  def cinema_header(cinema, label)
    cinema["url"] ? "<b><a href=\"#{cinema["url"]}\">#{label}</a></b>" : "<b>#{label}</b>"
  end

  def format_date(date_str)
    date = Date.parse(date_str)
    "#{date.strftime("%a")} #{date_str}"
  end
end

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  WeeklyNotifier.new(
    sensacine: SensacineAdapter.new,
    tmdb:      TmdbAdapter.new(api_key: ENV.fetch("TMDB_API_KEY")),
    telegram:  TelegramAdapter.new(
      token:   ENV.fetch("TELEGRAM_BOT_TOKEN"),
      chat_id: ENV.fetch("TELEGRAM_CHAT_ID")
    ),
    cinemas: CINEMAS
  ).run
end
