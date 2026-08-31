#!/usr/bin/env ruby
# frozen_string_literal: true

# Asks whether the director is a signal we can match films on across providers.
#
# The first run of this probe settled the earlier question: TMDB does NOT
# recognise an edition-suffixed title. "Harry Potter y la Piedra Filosofal 25
# Aniversario" and "The Fast & The Furious 25 aniversario" both come back with
# no results at all, and the one suffixed title TMDB did answer — SensaCine's
# "The Fast and the Furious (A todo gas) - 25 Aniversario" — it answered wrongly,
# with "Fast & Furious X" (2023). So a title alone cannot identify a film, and
# TMDB cannot be trusted to repair one.
#
# The director might. Yelmo publishes a clean "Director" per film ("Chris
# Columbus"); SensaCine publishes a "credits" array that bin/capture_fixtures.rb
# drops, so no fixture has ever shown its shape. This probe prints both sides so
# three things can be decided:
#
#   1. how the director is marked inside SensaCine's credits;
#   2. whether the two providers spell a director's name the same way;
#   3. whether credits are populated at all on re-releases and odd entries —
#      the films that need the help.
#
# Run it through the "Capture API fixtures" workflow with provider=identity.
# Read-only: it asks the providers and prints what they said.

require "bundler/setup"
require "json"
require "date"
require_relative "../lib/vo_cinema"

DAYS    = VoCinema::WeeklyNotifier::WEEK_DAYS
CINEMAS = VoCinema::Cinema.all

def section(title) = puts("\n\n########## #{title} ##########\n")

def sensacine_http = @sensacine_http ||= VoCinema::Http::Client.new(headers: VoCinema::Showtimes::Sensacine::HEADERS)
def yelmo_http     = @yelmo_http     ||= VoCinema::Http::Client.new(headers: VoCinema::Showtimes::Yelmo::HEADERS)

def parse(response) = response.code == "200" ? JSON.parse(response.body) : nil

# The domain objects carry title, date and time and nothing else, so the probe
# reads the raw payloads: the director is exactly the field they drop.
def sensacine_day(cinema, date)
  url    = "#{VoCinema::Showtimes::Sensacine::DOMAIN}/_/showtimes/theater-#{cinema.sensacine_id}/d-#{date}/"
  parsed = parse(sensacine_http.get(url))

  parsed && !parsed["error"] ? parsed["results"].to_a : []
end

def yelmo_city(city_key)
  parsed = parse(yelmo_http.post(
                   "#{VoCinema::Showtimes::Yelmo::DOMAIN}/now-playing.aspx/GetNowPlaying",
                   JSON.generate({ cityKey: city_key })
                 ))

  parsed&.dig("d", "Cinemas") || []
end

# What a credit looks like is the open question, so this tries the shapes
# Allociné's GraphQL is known to use and reports which one answered.
def director_from(credits)
  Array(credits).filter_map do |credit|
    position = credit["position"]
    marker   = position.is_a?(Hash) ? (position["name"] || position["department"]) : position
    next unless marker.to_s.upcase.include?("DIRECT")

    person = credit["person"] || {}
    [person["firstName"], person["lastName"]].compact.join(" ").strip
  end.reject(&:empty?).uniq
end

def showtimes_of(entry)
  (entry["showtimes"] || {}).values.flatten.compact
end

# ---------------------------------------------------------------------------
section "Reading both providers for every cinema they both cover"

shared = CINEMAS.select { |cinema| cinema.sensacine_id && cinema.yelmo_id }
puts "Cinemas covered twice: #{shared.map(&:name).inspect}"

# [date, time] => { sensacine: [[title, director], ...], yelmo: [...] }
slots           = Hash.new { |all, slot| all[slot] = { sensacine: [], yelmo: [] } }
directors       = Hash.new { |all, provider| all[provider] = {} }
credit_samples  = []
missing_credits = []

shared.each do |cinema|
  DAYS.times do |offset|
    date = (VoCinema::Clock.today + offset).to_s

    sensacine_day(cinema, date).each do |entry|
      movie    = entry["movie"] || {}
      title    = movie["title"] || "(untitled)"
      found    = director_from(movie["credits"])
      director = found.first

      credit_samples << [title, movie["credits"]] if credit_samples.length < 3
      missing_credits << title if director.nil?
      directors[:sensacine][title] = director

      showtimes_of(entry).each do |showtime|
        time = showtime["startsAt"].to_s.slice(11, 5)
        slots[[date, time]][:sensacine] << [title, director] if time
      end
    end
  end

  city = cinema.yelmo_id.to_s.split("/").first
  venue = yelmo_city(city).find { |one| one["Key"] == cinema.yelmo_id.to_s.split("/").last }
  next unless venue

  (venue["Dates"] || []).each do |day|
    date = Time.at(day["FilterDate"].to_s[/\d+/].to_i / 1000).utc.strftime("%Y-%m-%d")

    (day["Movies"] || []).each do |movie|
      title    = movie["Title"] || "(untitled)"
      director = movie["Director"].to_s.strip
      director = nil if director.empty?
      directors[:yelmo][title] = director

      (movie["Formats"] || []).each do |format|
        (format["Showtimes"] || []).each do |showtime|
          time = showtime["Time"].to_s.slice(0, 5)
          slots[[date, time]][:yelmo] << [title, director] unless time.empty?
        end
      end
    end
  end
end

# ---------------------------------------------------------------------------
section "How SensaCine marks a director inside credits"

puts "Films with no director extracted: #{missing_credits.uniq.length} of #{directors[:sensacine].length}"
puts "  #{missing_credits.uniq.inspect}\n\n"

credit_samples.each do |title, credits|
  puts "--- #{title.inspect} ---"
  puts JSON.pretty_generate(Array(credits).first(4))
  puts
end

# ---------------------------------------------------------------------------
section "Do the two providers name the same director?"

agreed = 0

directors[:sensacine].each do |title, director|
  match = directors[:yelmo].find { |other, _| other.downcase.strip == title.downcase.strip }
  next unless match

  agree   = director && match.last && director.casecmp?(match.last)
  agreed += 1 if agree
  puts format("  %-52s %-24s %-24s %s", title[0, 50].inspect, director.inspect, match.last.inspect,
              agree ? "agree" : "DIFFER")
end

puts "\n#{agreed} film(s) both providers spell identically also agree on the director."

# ---------------------------------------------------------------------------
section "The films that fail to group — would the director rescue them?"

# The previous probe paired every SensaCine screening with every Yelmo screening
# at the same minute, which counted two different films in two screens as a
# failure to group. This asks the real question: at this minute, which titles
# does one provider list that the other does not match by key?
unmatched = 0

slots.sort.each do |(date, time), sides|
  next if sides[:sensacine].empty? || sides[:yelmo].empty?

  yelmo_keys     = sides[:yelmo].map { |title, _| title.downcase.strip }
  sensacine_keys = sides[:sensacine].map { |title, _| title.downcase.strip }

  orphans = sides[:sensacine].reject { |title, _| yelmo_keys.include?(title.downcase.strip) }
  next if orphans.empty?

  candidates = sides[:yelmo].reject { |title, _| sensacine_keys.include?(title.downcase.strip) }
  next if candidates.empty?

  unmatched += orphans.length
  puts "  #{date} #{time}"
  orphans.uniq.each { |title, director| puts "    sensacine: #{title.inspect} dir=#{director.inspect}" }
  candidates.uniq.each { |title, director| puts "    yelmo    : #{title.inspect} dir=#{director.inspect}" }
end

puts "\n#{unmatched} screening(s) where one provider's title found no match on the other side."

puts "\n\nDone."
