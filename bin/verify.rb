#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "date"

THEATER_ID   = "E0628"
TMDB_API_KEY = ENV.fetch("TMDB_API_KEY")

HEADERS = {
  "User-Agent"      => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  "Accept"          => "application/json",
  "Accept-Language" => "es-ES,es;q=0.9",
  "Referer"         => "https://www.sensacine.com/cines/cine/#{THEATER_ID}/"
}.freeze

# Known Spanish-title films to test TMDB matching accuracy.
# Format: [spanish_title, year, expected_english_title]
TMDB_TEST_FILMS = [
  ["La sustancia",     2024, "The Substance"],
  ["Anora",            2024, "Anora"],
  ["El 47",            2024, "El 47"],
  ["Emilia Pérez",     2024, "Emilia Pérez"],
  ["Conclave",         2024, "Conclave"],
].freeze

def get(url)
  uri = URI(url)
  req = Net::HTTP::Get.new(uri, HEADERS)
  Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 10) { |h| h.request(req) }
end

def separator(title)
  puts
  puts "=" * 60
  puts "  #{title}"
  puts "=" * 60
end

# ── 1. SensaCine endpoint ────────────────────────────────────────
separator("SensaCine /_/showtimes/ endpoint")

date = Date.today.to_s
url  = "https://www.sensacine.com/_/showtimes/theater-#{THEATER_ID}/d-#{date}/p-1/"
puts "GET #{url}"

resp = get(url)
puts "HTTP #{resp.code}"

if resp.code == "200"
  data       = JSON.parse(resp.body)
  pagination = data["pagination"] || {}
  results    = data["results"]    || []

  puts "Pages: #{pagination["page"]}/#{pagination["totalPages"]}"
  puts "Films on this page: #{results.size}"
  puts

  results.first(3).each do |entry|
    title     = entry.dig("movie", "title") || "(no title)"
    original  = (entry.dig("showtimes", "original") || []).size
    dubbed    = (entry.dig("showtimes", "dubbed")   || []).size
    local     = (entry.dig("showtimes", "local")    || []).size

    sample_version = entry.dig("showtimes", "original", 0, "diffusionVersion") ||
                     entry.dig("showtimes", "local",    0, "diffusionVersion")

    puts "  #{title}"
    puts "    original=#{original} dubbed=#{dubbed} local=#{local}  diffusionVersion=#{sample_version.inspect}"
  end
else
  puts "Body (first 500 chars):"
  puts resp.body.to_s[0, 500]
  puts
  puts "SENSACINE_REACHABLE=false"
  exit 1
end

puts
puts "SENSACINE_REACHABLE=true"

# ── 2. TMDB title matching ───────────────────────────────────────
separator("TMDB Spanish title matching")

hits = 0

TMDB_TEST_FILMS.each do |spanish_title, year, expected|
  encoded = URI.encode_www_form_component(spanish_title)
  url     = "https://api.themoviedb.org/3/search/movie?api_key=#{TMDB_API_KEY}&query=#{encoded}&primary_release_year=#{year}&language=es-ES"
  resp    = get(url)

  if resp.code != "200"
    puts "  [#{spanish_title}] HTTP #{resp.code} — TMDB unreachable"
    next
  end

  results = JSON.parse(resp.body)["results"] || []

  if results.empty?
    puts "  [#{spanish_title}] NO RESULTS"
    next
  end

  top    = results[0]
  second = results[1]
  ratio  = second ? (top["popularity"].to_f / second["popularity"].to_f).round(1) : Float::INFINITY

  matched_title    = top["title"]
  original_title   = top["original_title"]
  vote_average     = top["vote_average"]
  ambiguous        = ratio < 2.0 && second

  status = if ambiguous
    "AMBIGUOUS (ratio #{ratio}×)"
  elsif matched_title&.downcase == expected.downcase || original_title&.downcase == expected.downcase
    "OK"
  else
    "MISMATCH"
  end

  hits += 1 if status == "OK"

  puts "  [#{spanish_title} #{year}]"
  puts "    status=#{status}  matched=#{matched_title.inspect}  original=#{original_title.inspect}  ★#{vote_average}  ratio=#{ratio}×"
end

puts
puts "TMDB_MATCH_SCORE=#{hits}/#{TMDB_TEST_FILMS.size}"
