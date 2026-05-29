#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "date"
require "yaml"

TELEGRAM_BOT_TOKEN     = ENV.fetch("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID       = ENV.fetch("TELEGRAM_CHAT_ID")
TMDB_API_KEY           = ENV.fetch("TMDB_API_KEY")
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

# ---------------------------------------------------------------------------
# Null objects
# ---------------------------------------------------------------------------

class NullRating
  def score        = nil
  def formatted    = nil
  def present?     = false
end

Rating = Data.define(:score) do
  def formatted = format("★ %.1f", score)
  def present?  = true
end

# ---------------------------------------------------------------------------
# HTTP helper
# ---------------------------------------------------------------------------

def http_get(url, headers = {}, retried: false)
  sleep(1.5 + rand)
  uri = URI(url)
  req = Net::HTTP::Get.new(uri, headers)
  resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 10) { |h| h.request(req) }
  return resp if resp.code == "200" || retried

  puts "Retrying #{url}"
  http_get(url, headers, retried: true)
end

# ---------------------------------------------------------------------------
# SensacineAdapter
# ---------------------------------------------------------------------------

class SensacineAdapter
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

    results = JSON.parse(resp.body)["results"] || []
    sessions = []

    results.each do |entry|
      localized_title = entry.dig("movie", "title") || "(untitled)"
      year            = entry.dig("movie", "release", "year")
      film            = Film.new(localized_title: localized_title, year: year)

      UNFILTERED_BUCKETS.each do |bucket|
        original_version = VO_BUCKETS.include?(bucket)

        (entry.dig("showtimes", bucket) || []).each do |showtime|
          starts_at = showtime["startsAt"]&.slice(11, 5)
          next unless starts_at

          sessions << ScreeningSession.new(
            film:              film,
            date:              date,
            starts_at:         starts_at,
            original_version?: original_version
          )
        end
      end
    end

    sessions
  end
end

# ---------------------------------------------------------------------------
# TmdbAdapter
# ---------------------------------------------------------------------------

class TmdbAdapter
  def fetch_original_title(film)
    results = search(film.localized_title, film.year)
    top = results&.first
    top&.dig("original_title")
  end

  def rating_for(film)
    results = search(film.title || film.localized_title, film.year)
    return NullRating.new if results.nil? || results.empty?

    top    = results[0]
    second = results[1]

    return NullRating.new if top["vote_count"].to_i.zero?

    top_score    = top["vote_average"].to_f
    second_score = (second&.dig("vote_average") || 0).to_f
    return NullRating.new if second_score > 0 && top_score / second_score < TMDB_AMBIGUITY_RATIO

    Rating.new(score: top_score)
  end

  private

  def search(title, year = nil)
    query = URI.encode_www_form(query: title, language: "es-ES", api_key: TMDB_API_KEY)
    query += "&year=#{year}" if year
    resp = http_get("https://api.themoviedb.org/3/search/movie?#{query}")
    return nil unless resp.code == "200"

    JSON.parse(resp.body)["results"] || []
  end
end

# ---------------------------------------------------------------------------
# Rendering helpers
# ---------------------------------------------------------------------------

def cinema_header(cinema, label)
  return "<b>#{label}</b>" unless cinema["url"]
  "<b><a href=\"#{cinema["url"]}\">#{label}</a></b>"
end

def format_date(date_str)
  date = Date.parse(date_str)
  "#{date.strftime("%a")} #{date_str}"
end

def telegram_send(text)
  uri = URI("https://api.telegram.org/bot#{TELEGRAM_BOT_TOKEN}/sendMessage")
  req = Net::HTTP::Post.new(uri)
  req.content_type = "application/json"
  req.body = JSON.generate(chat_id: TELEGRAM_CHAT_ID, text: text, parse_mode: "HTML")
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

today       = Date.today
sensacine   = SensacineAdapter.new
tmdb        = TmdbAdapter.new
lines       = []
no_vo_cinemas = []

CINEMAS.each do |cinema|
  all_sessions = []

  WEEK_DAYS.times do |offset|
    date     = (today + offset).to_s
    sessions = sensacine.fetch_theater_movie_sessions(date: date, theater_id: cinema["id"])
    sessions = sessions.select(&:original_version?) if cinema["check_vo"]
    all_sessions.concat(sessions)
  end

  if all_sessions.empty?
    no_vo_cinemas << cinema["name"]
    next
  end

  week_end = (today + WEEK_DAYS - 1).to_s
  lines << cinema_header(cinema, "#{cinema["name"]} — #{today} → #{week_end}")

  unique_films = all_sessions.map(&:film).uniq
  unique_films.each do |film|
    original_title = tmdb.fetch_original_title(film)
    film.title = original_title
  end

  films_with_sessions = unique_films.map do |film|
    rating   = tmdb.rating_for(film)
    sessions = all_sessions.select { |s| s.film == film }
    [film, rating, sessions]
  end

  films_with_sessions.each do |film, rating, sessions|
    title_line = "<b>#{film.localized_title}</b>"
    if film.title && film.title.downcase != film.localized_title.downcase
      title_line += " <i>(#{film.title})</i>"
    end
    title_line += " #{rating.formatted}" if rating.present?

    lines << ""
    lines << title_line

    dates_map = sessions.group_by(&:date).transform_values { |ss| ss.map(&:starts_at).sort.uniq }
    dates_map = dates_map.sort.to_h

    if dates_map.keys.length == WEEK_DAYS
      all_times = dates_map.values.flatten.sort.uniq
      lines << "  All week: #{dates_map.keys.min} → #{dates_map.keys.max}: #{all_times.join(", ")}"
    else
      dates_map.each do |date, times|
        lines << "  #{format_date(date)}: #{times.join(", ")}"
      end
    end
  end

  lines << ""
end

unless no_vo_cinemas.empty?
  lines << "The following venues had no VO sessions: #{no_vo_cinemas.join(", ")}"
  lines << ""
end

message = lines.join("\n").strip
message = message[0, TELEGRAM_MAX_MSG_CHARS] + "\n... (truncated)" if message.length > TELEGRAM_MAX_MSG_CHARS

telegram_send(message)
puts "Sent #{message.length} chars to Telegram"
