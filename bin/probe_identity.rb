#!/usr/bin/env ruby
# frozen_string_literal: true

# Answers the one question canonical film identity hangs on: can TMDB recognise
# the same film through the different names the providers give it?
#
# Ocimax is the only cinema both providers cover, and they disagree about what
# films are called there — SensaCine says "Harry Potter y la Piedra Filosofal"
# where Yelmo says "…25 Aniversario". Records that spell a film differently
# never group, so the union merge rule never fires for them. If TMDB resolves
# both spellings to one id, that id is the identity we have been missing.
#
# Run it through the "Capture API fixtures" workflow with provider=identity.
# Read-only: it asks the providers and prints what they said.

require "bundler/setup"
require "json"
require "date"
require "uri"
require_relative "../lib/vo_cinema"

DAYS    = VoCinema::WeeklyNotifier::WEEK_DAYS
CINEMAS = VoCinema::Cinema.all

def section(title) = puts("\n\n########## #{title} ##########\n")

# The probe wants raw TMDB fields — id and release_date — that Movies::Tmdb has
# no reason to expose, so it asks over the same client with the same query.
def tmdb_top_match(title, year)
  key = ENV["TMDB_API_KEY"].to_s
  return nil if key.empty?

  query  = URI.encode_www_form(query: title, language: "es-ES", api_key: key)
  query += "&year=#{year}" if year
  response = tmdb_http.get("#{VoCinema::Movies::Tmdb::DOMAIN}/3/search/movie?#{query}")
  return nil unless response.code == "200"

  JSON.parse(response.body)["results"].to_a.first
end

def tmdb_http = @tmdb_http ||= VoCinema::Http::Client.new

# ---------------------------------------------------------------------------
section "The week at every cinema both providers cover"

shared = CINEMAS.select { |cinema| cinema.sensacine_id && cinema.yelmo_id }
puts "Cinemas covered twice: #{shared.map(&:name).inspect}"

sensacine = VoCinema::Showtimes::Sensacine.new
yelmo     = VoCinema::Showtimes::Yelmo.new
titles    = Hash.new { |seen, provider| seen[provider] = [] }
overlaps  = []

shared.each do |cinema|
  DAYS.times do |offset|
    date = (Date.today + offset).to_s
    from_sensacine = sensacine.sessions_for(cinema, date)
    from_yelmo     = yelmo.sessions_for(cinema, date)

    titles[:sensacine].concat(from_sensacine.map { |s| [s.film.localized_title, s.film.year] })
    titles[:yelmo].concat(from_yelmo.map { |s| [s.film.localized_title, s.film.year] })

    from_sensacine.each do |one|
      from_yelmo.select { |other| other.starts_at == one.starts_at }.each do |other|
        overlaps << [date, one.starts_at, one.film.localized_title, other.film.localized_title]
      end
    end
  end
end

# ---------------------------------------------------------------------------
section "Screenings both providers report — do they group today?"

puts "#{overlaps.length} slot(s) where both providers list a screening at the same minute.\n\n"
grouped, split = overlaps.partition { |_, _, a, b| a.downcase.strip == b.downcase.strip }
puts "  group today     : #{grouped.length}"
puts "  fail to group   : #{split.length}   <- what canonical identity would buy\n\n"

split.uniq { |_, _, a, b| [a, b] }.each do |date, time, from_sensacine, from_yelmo|
  puts "  #{date} #{time}"
  puts "    sensacine: #{from_sensacine.inspect}"
  puts "    yelmo    : #{from_yelmo.inspect}"
end

# ---------------------------------------------------------------------------
section "Does TMDB resolve every spelling of a film to one id?"

by_tmdb_id = Hash.new { |films, id| films[id] = [] }

titles.each do |provider, seen|
  seen.uniq.each do |title, year|
    match = tmdb_top_match(title, year)
    label = match ? "id=#{match["id"]} #{match["title"].inspect} (#{match["release_date"]})" : "NO MATCH"
    puts format("  %-10s %-52s -> %s", provider, title[0, 50].inspect, label)
    by_tmdb_id[match&.fetch("id")] << [provider, title]
  end
end

puts "\nProvider titles grouped by the TMDB id they resolved to:\n\n"
by_tmdb_id.each do |id, entries|
  next if entries.length < 2 && id

  puts "  #{id ? "id=#{id}" : "NO MATCH"}"
  entries.each { |provider, title| puts "    #{provider}: #{title.inspect}" }
end

# ---------------------------------------------------------------------------
section "One SensaCine movie object, unpruned"

# bin/capture_fixtures.rb drops credits and cast, so the fixtures cannot answer
# whether SensaCine carries an external id or a director to match Yelmo's on.
cinema   = shared.first || CINEMAS.first
url      = "#{VoCinema::Showtimes::Sensacine::DOMAIN}/_/showtimes/theater-#{cinema.sensacine_id}/d-#{Date.today}/"
response = VoCinema::Http::Client.new(headers: VoCinema::Showtimes::Sensacine::HEADERS).get(url)
entry    = response.code == "200" ? JSON.parse(response.body)["results"].to_a.first : nil

if entry
  movie = entry["movie"]
  puts "Every key on movie: #{movie.keys.sort.inspect}\n\n"
  movie.each do |key, value|
    next if %w[synopsis synopsis_json synopsisFull poster].include?(key)

    puts format("  %-16s %s", key, value.inspect[0, 160])
  end
else
  puts "No results for #{cinema.name} today (HTTP #{response.code}) — try again earlier in the day."
end

puts "\n\nDone."
