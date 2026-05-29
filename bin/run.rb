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
VO_BUCKETS             = %w[original local].freeze
UNFILTERED_BUCKETS     = %w[original local dubbed].freeze
WEEK_DAYS              = 7
TMDB_AMBIGUITY_RATIO   = 2.0

CINEMAS = YAML.load_file(File.join(__dir__, "..", "config", "cinemas.yml"))["cinemas"].freeze

SENSACINE_HEADERS = {
  "User-Agent"      => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  "Accept"          => "application/json",
  "Accept-Language" => "es-ES,es;q=0.9",
  "Referer"         => "https://www.sensacine.com/cines/cine/"
}.freeze

def http_get(url, headers = {}, retried: false)
  sleep(1.5 + rand) # 1.5–2.5 s jitter between requests
  uri = URI(url)
  req = Net::HTTP::Get.new(uri, headers)
  resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 10) { |h| h.request(req) }
  return resp if resp.code == "200" || retried

  puts "Retrying #{url}"
  http_get(url, headers, retried: true)
end

def telegram_send(text)
  uri = URI("https://api.telegram.org/bot#{TELEGRAM_BOT_TOKEN}/sendMessage")
  req = Net::HTTP::Post.new(uri)
  req.content_type = "application/json"
  req.body = JSON.generate(chat_id: TELEGRAM_CHAT_ID, text: text, parse_mode: "HTML")
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
end

# Returns { rating: "★ X.X", original_title: "..." } or nil if ambiguous / not found.
def tmdb_info(title, year = nil)
  query = URI.encode_www_form(query: title, language: "es-ES", api_key: TMDB_API_KEY)
  query += "&year=#{year}" if year
  url  = "https://api.themoviedb.org/3/search/movie?#{query}"
  resp = http_get(url)
  return nil unless resp.code == "200"

  results = JSON.parse(resp.body)["results"] || []
  top    = results[0]
  second = results[1]

  return nil if results.empty? || top["vote_count"].to_i.zero?

  top_score    = top["vote_average"].to_f
  second_score = (second&.dig("vote_average") || 0).to_f
  return nil if second_score > 0 && top_score / second_score < TMDB_AMBIGUITY_RATIO

  {
    rating:         format("★ %.1f", top_score),
    original_title: top["original_title"]
  }
end

def cinema_header(cinema, label)
  return "<b>#{label}</b>" unless cinema["url"]
  "<b><a href=\"#{cinema["url"]}\">#{label}</a></b>"
end

def format_date(date_str)
  date = Date.parse(date_str)
  "#{date.strftime("%a")} #{date_str}"
end

# Returns { title => { year:, dates: { date_str => [times] } } } for screenings.
# check_vo: true restricts to VO buckets; false collects all (assumes venue is VOSE).
def fetch_week(theater_id, start_date, check_vo: false)
  films = {}
  buckets = check_vo ? VO_BUCKETS : UNFILTERED_BUCKETS

  WEEK_DAYS.times do |offset|
    date = (start_date + offset).to_s
    url  = "https://www.sensacine.com/_/showtimes/theater-#{theater_id}/d-#{date}/p-1/"

    puts "GET #{url}"
    resp = http_get(url, SENSACINE_HEADERS)
    puts "HTTP #{resp.code}"

    next unless resp.code == "200"

    results = JSON.parse(resp.body)["results"] || []

    results.each do |entry|
      title = entry.dig("movie", "title") || "(untitled)"
      year  = entry.dig("movie", "release", "year")

      times = buckets.flat_map do |bucket|
        (entry.dig("showtimes", bucket) || []).map { |s| s["startsAt"]&.slice(11, 5) }
      end.compact.sort.uniq

      next if times.empty?

      films[title] ||= { year: year, dates: {} }
      (films[title][:dates][date] ||= []).concat(times).sort!.uniq!
    end
  end

  films
end

today = Date.today
lines = []
no_vo_cinemas = []

CINEMAS.each do |cinema|
  films = fetch_week(cinema["id"], today, check_vo: cinema["check_vo"])

  if films.empty?
    no_vo_cinemas << cinema["name"]
    next
  end

  week_end = (today + WEEK_DAYS - 1).to_s
  lines << cinema_header(cinema, "#{cinema["name"]} — #{today} → #{week_end}")

  films.each do |title, info|
    tmdb   = tmdb_info(title, info[:year])
    rating = tmdb&.dig(:rating)
    orig   = tmdb&.dig(:original_title)

    title_line = "<b>#{title}</b>"
    title_line += " <i>(#{orig})</i>" if orig && orig.downcase != title.downcase
    title_line += " #{rating}"        if rating

    lines << ""
    lines << title_line

    dates = info[:dates]
    if dates.keys.length == WEEK_DAYS
      all_times = dates.values.flatten.sort.uniq
      lines << "  All week: #{dates.keys.min} → #{dates.keys.max}: #{all_times.join(", ")}"
    else
      dates.each do |date, times|
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
