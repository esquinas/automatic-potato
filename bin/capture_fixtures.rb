#!/usr/bin/env ruby
# frozen_string_literal: true

# Prints real, live API payloads to the CI log so the fixtures under
# test/fixtures/ can be refreshed from production data instead of guesswork.
#
# Run it through the "Capture API fixtures" workflow (workflow_dispatch), then
# copy each block between its BEGIN/END markers into the matching fixture file.
#
# Bodies are pruned: long prose and image blobs are dropped or truncated so the
# fixtures stay readable. Every key the production code actually reads is kept
# verbatim, and a key inventory is printed alongside so it is obvious what was
# left out.

require "bundler/setup"
require "json"
require "date"
require_relative "../lib/vo_cinema"

DROPPED_KEYS  = %w[synopsis synopsis_json poster cast videos trailer
                   editorialReviews relatedTags stats customJson Poster
                   PosterUrl TrailerUrl Synopsis Description].freeze
MAX_STRING    = 120
CINEMAS       = VoCinema::Cinema.all.freeze
# Set PROVIDER to sensacine, yelmo or tmdb to capture just that one; the job
# log for a single provider is short enough to read end to end.
PROVIDER      = (ENV["PROVIDER"] || "all").downcase
DAYS          = 7

def section(title) = puts("\n\n########## #{title} ##########\n")
def begin_fixture(name) = puts("\n===== BEGIN fixture: #{name} =====")
def end_fixture(name)   = puts("===== END fixture: #{name} =====\n")

def capturing?(provider) = [provider, "all"].include?(PROVIDER)

def dump(name, value)
  begin_fixture(name)
  puts JSON.pretty_generate(value)
  end_fixture(name)
end

def prune(value)
  case value
  when Hash   then prune_hash(value)
  when Array  then value.map { |v| prune(v) }
  when String then value.length > MAX_STRING ? "#{value[0, MAX_STRING]}…" : value
  else value
  end
end

def prune_hash(hash)
  kept = hash.reject { |key, _| DROPPED_KEYS.include?(key) }
  kept = kept.merge("credits" => directors_in(kept["credits"])) if kept.key?("credits")

  kept.transform_values { |value| prune(value) }
end

# credits lists the whole crew, and only the director is ever read — Yelmo
# publishes one too, which is what lets the two providers be matched on it.
# Keeping the rest would bury the fixture; dropping the lot, as this used to,
# left no fixture able to show the field the matching depends on.
def directors_in(credits)
  Array(credits).select { |credit| credit.dig("position", "name") == "DIRECTOR" }
end

# Every request goes through the service's own client, with the service's own
# headers: a payload captured here is one the notifier could really have got.
def sensacine_http = @sensacine_http ||= VoCinema::Http::Client.new(headers: VoCinema::Showtimes::Sensacine::HEADERS)
def yelmo_http     = @yelmo_http     ||= VoCinema::Http::Client.new(headers: VoCinema::Showtimes::Yelmo::HEADERS)
def tmdb_http      = @tmdb_http      ||= VoCinema::Http::Client.new

def parse_json(resp)
  JSON.parse(resp.body)
rescue JSON::ParserError => e
  puts "  !! could not parse JSON: #{e.message}"
  nil
end

# ---------------------------------------------------------------------------
if capturing?("sensacine")
section "SensaCine — every cinema, next #{DAYS} days"

empty_day_body   = nil
sample_day       = nil
vo_entries       = []
movie_keys       = []
showtime_keys    = []
diffusion_values = Hash.new(0)
bucket_totals    = Hash.new(0)

CINEMAS.each do |cinema|
  puts "\n--- #{cinema.name} (id=#{cinema.sensacine_id}) ---"

  DAYS.times do |offset|
    date = (VoCinema::Clock.today + offset).to_s
    url  = "#{VoCinema::Showtimes::Sensacine::DOMAIN}/_/showtimes/theater-#{cinema.sensacine_id}/d-#{date}/"
    resp = sensacine_http.get(url)

    unless resp.code == "200"
      puts "  #{date}  HTTP #{resp.code}"
      next
    end

    parsed = parse_json(resp) or next

    if parsed["error"]
      empty_day_body ||= parsed
      puts "  #{date}  error=#{parsed["message"].inspect} nextDate=#{parsed["nextDate"].inspect}"
      next
    end

    results    = parsed["results"] || []
    films_seen = []

    results.each do |entry|
      movie_keys |= (entry["movie"] || {}).keys
      buckets = (entry["showtimes"] || {}).reject { |_, v| v.nil? || v.empty? }
      next if buckets.empty?

      buckets.each do |bucket, showtimes|
        bucket_totals[bucket] += showtimes.length
        showtimes.each do |showtime|
          showtime_keys |= showtime.keys
          diffusion_values[[bucket, showtime["diffusionVersion"]]] += 1
        end
      end

      films_seen << "#{entry.dig("movie", "title")} #{buckets.transform_values(&:length).inspect}"

      sample_day ||= { cinema: cinema.name, date: date, body: parsed }
      if buckets.keys.any? { |bucket| bucket.start_with?("original", "local") }
        vo_entries << { cinema: cinema.name, date: date, entry: entry }
      end
    end

    puts "  #{date}  results=#{results.length} " \
         "totalPages=#{parsed.dig("pagination", "totalPages").inspect}  #{films_seen.join(" | ")}"
  end
end

puts "\nBucket totals across every cinema and day: #{bucket_totals.sort.to_h.inspect}"
puts "movie.* keys seen      : #{movie_keys.sort.inspect}"
puts "showtime.* keys seen   : #{showtime_keys.sort.inspect}"
puts "[bucket, diffusionVersion] counts: #{diffusion_values.sort_by { |k, _| k.map(&:to_s) }.to_h.inspect}"

dump("sensacine/empty_day.json", empty_day_body) if empty_day_body

if sample_day
  puts "\n(a normal day: #{sample_day[:cinema]} on #{sample_day[:date]}, trimmed to three films)"
  trimmed = sample_day[:body].merge("results" => (sample_day[:body]["results"] || []).first(3))
  dump("sensacine/ocimax_all_dubbed.json", prune(trimmed))
end

if vo_entries.empty?
  puts "\nNo cinema in Gijón had a showtime outside the dubbed buckets this week, so there is\n" \
       "nothing to refresh sensacine/laboral_original_version.json from. Leave it as it is."
else
  puts "\n(original-version screenings at #{vo_entries.map { |e| e[:cinema] }.uniq.join(", ")})"
  day = sample_day[:body].merge("results" => vo_entries.first(3).map { |e| e[:entry] })
  dump("sensacine/laboral_original_version.json", prune(day))
end
end

# ---------------------------------------------------------------------------
if capturing?("yelmo")
section "Yelmo — GetNowPlaying for Asturias"

yelmo_resp = yelmo_http.post(
  "#{VoCinema::Showtimes::Yelmo::DOMAIN}/now-playing.aspx/GetNowPlaying",
  JSON.generate({ cityKey: "asturias" })
)
puts "HTTP #{yelmo_resp.code}"

if yelmo_resp.code == "200" && (yelmo = parse_json(yelmo_resp))
  cinemas = yelmo.dig("d", "Cinemas") || []
  puts "Cinema keys: #{cinemas.map { |c| c["Key"] }.inspect}"

  ocimax = cinemas.find { |c| c["Key"] == "ocimax-gijon" } || cinemas.first
  if ocimax
    dates     = ocimax["Dates"] || []
    languages = Hash.new(0)
    dates.each do |date_entry|
      (date_entry["Movies"] || []).each do |movie|
        (movie["Formats"] || []).each { |f| languages[f["Language"]] += 1 }
      end
    end
    puts "FilterDate samples : #{dates.first(3).map { |d| d["FilterDate"] }.inspect}"
    puts "Format.Language values seen: #{languages.sort_by { |_, v| -v }.to_h.inspect}"
    puts "Movie.* keys  : #{(dates.dig(0, "Movies", 0) || {}).keys.sort.inspect}"
    puts "Format.* keys : #{(dates.dig(0, "Movies", 0, "Formats", 0) || {}).keys.sort.inspect}"
    puts "Showtime.* keys: #{(dates.dig(0, "Movies", 0, "Formats", 0, "Showtimes", 0) || {}).keys.sort.inspect}"

    trimmed = ocimax.merge("Dates" => dates.first(2).map { |d| d.merge("Movies" => (d["Movies"] || []).first(3)) })
    dump("yelmo/now_playing_asturias.json", prune({ "d" => { "Cinemas" => [trimmed] } }))
  end
end
end

# ---------------------------------------------------------------------------
if capturing?("tmdb")
section "TMDB — searches for films really showing in Gijón"

tmdb_key = ENV["TMDB_API_KEY"].to_s
if tmdb_key.empty?
  puts "TMDB_API_KEY not set — skipping"
else
  [
    ["Una noche al año",                     2026, "search_una_noche_al_ano.json"],
    ["Harry Potter y la Piedra Filosofal",   2001, "search_harry_potter.json"],
    ["El ser querido",                       2026, "search_el_ser_querido.json"],
    ["La sustancia",                         2024, "search_la_sustancia.json"],
    ["La constelación del perro",            2026, "search_la_constelacion_del_perro.json"],
    ["Tadeo Jones y la lámpara maravillosa", 2026, "search_tadeo_jones.json"]
  ].each do |title, year, fixture|
    query = URI.encode_www_form(query: title, language: "es-ES", api_key: tmdb_key)
    resp  = tmdb_http.get("#{VoCinema::Movies::Tmdb::DOMAIN}/3/search/movie?#{query}&year=#{year}")
    puts "\n#{title} (#{year}) → HTTP #{resp.code}"
    next unless resp.code == "200"

    parsed  = parse_json(resp) or next
    results = (parsed["results"] || []).first(3)
    results.each do |r|
      puts "  #{r["title"].inspect} / #{r["original_title"].inspect} " \
           "lang=#{r["original_language"].inspect} score=#{r["vote_average"]} votes=#{r["vote_count"]}"
    end
    dump("tmdb/#{fixture}", prune(parsed.merge("results" => results)))
  end
end
end

puts "\n\nDone."
