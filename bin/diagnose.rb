#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "date"
require "yaml"

def http_get(url, headers = {})
  uri = URI(url)
  req = Net::HTTP::Get.new(uri, headers)
  Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 15) { |h| h.request(req) }
end

def ok(msg)   = puts "[OK]   #{msg}"
def fail!(msg) = puts "[FAIL] #{msg}"
def section(title) = puts("\n== #{title} ==")

# ---------------------------------------------------------------------------
section "TMDB API key"
tmdb_key = ENV["TMDB_API_KEY"]
if tmdb_key.nil? || tmdb_key.empty?
  fail! "TMDB_API_KEY not set"
else
  resp = http_get("https://api.themoviedb.org/3/configuration?api_key=#{tmdb_key}")
  if resp.code == "200"
    ok "Key valid (HTTP 200)"
  else
    fail! "HTTP #{resp.code} — #{resp.body[0, 300]}"
  end
end

# ---------------------------------------------------------------------------
section "Telegram bot token"
tg_token = ENV["TELEGRAM_BOT_TOKEN"]
tg_chat  = ENV["TELEGRAM_CHAT_ID"]

if tg_token.nil? || tg_token.empty?
  fail! "TELEGRAM_BOT_TOKEN not set"
else
  resp = http_get("https://api.telegram.org/bot#{tg_token}/getMe")
  body = JSON.parse(resp.body) rescue {}
  if resp.code == "200" && body["ok"]
    ok "Token valid — bot @#{body.dig("result", "username")}"
  else
    fail! "HTTP #{resp.code} — #{resp.body[0, 300]}"
  end
end

if tg_chat.nil? || tg_chat.empty?
  fail! "TELEGRAM_CHAT_ID not set"
else
  ok "TELEGRAM_CHAT_ID set (#{tg_chat})"
end

# ---------------------------------------------------------------------------
section "SensaCine probe (first cinema, 7 days)"
cinemas = YAML.load_file(File.join(__dir__, "..", "config", "cinemas.yml"))["cinemas"]
cinema  = cinemas.first
headers = {
  "User-Agent"      => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  "Accept"          => "application/json",
  "Accept-Language" => "es-ES,es;q=0.9",
  "Referer"         => "https://www.sensacine.com/cines/cine/"
}

puts "Cinema : #{cinema["name"]} (id=#{cinema["id"]})"

7.times do |offset|
  date = (Date.today + offset).to_s
  url  = "https://www.sensacine.com/_/showtimes/theater-#{cinema["id"]}/d-#{date}/"
  puts "\n--- #{date} ---"

  resp = http_get(url, headers)
  puts "HTTP: #{resp.code}"

  unless resp.code == "200"
    puts "Body: #{resp.body[0, 300]}"
    next
  end

  parsed  = JSON.parse(resp.body) rescue nil
  unless parsed
    puts "[FAIL] Could not parse JSON"
    next
  end

  if parsed["error"]
    puts "  API error: #{parsed["message"]} (nextDate: #{parsed["nextDate"]})"
    next
  end

  results    = parsed["results"] || []
  total_pages = parsed.dig("pagination", "totalPages")
  puts "  totalPages=#{total_pages}  results=#{results.length}"

  results.each do |entry|
    title    = entry.dig("movie", "title") || "(untitled)"
    showtimes = entry["showtimes"] || {}
    puts "  Film: #{title}"
    puts "    Showtime buckets: #{showtimes.keys.inspect}"
    showtimes.each do |bucket, sessions|
      sample = sessions.first&.dig("startsAt") || sessions.first&.dig("time") || "(no startsAt)"
      puts "    #{bucket}: #{sessions.length} session(s), sample startsAt=#{sample}"
    end
  end
  puts "  (no results for this date)" if results.empty?
end
