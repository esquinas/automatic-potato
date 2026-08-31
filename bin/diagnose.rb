#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks that the tokens still work and that SensaCine still answers, using the
# same clients the notifier uses — so a header or endpoint the service gets
# wrong is wrong here too, rather than passing a probe that asks differently.

require "bundler/setup"
require "json"
require "date"
require_relative "../lib/vo_cinema"

def ok(message)    = puts("[OK]   #{message}")
def failed(message) = puts("[FAIL] #{message}")
def section(title)  = puts("\n== #{title} ==")

http = VoCinema::Http::Client.new

section "TMDB API key"
tmdb_key = ENV["TMDB_API_KEY"].to_s
if tmdb_key.empty?
  failed "TMDB_API_KEY not set"
else
  response = http.get("#{VoCinema::Movies::Tmdb::DOMAIN}/3/configuration?api_key=#{tmdb_key}")
  response.code == "200" ? ok("Key valid") : failed("HTTP #{response.code} — #{response.body[0, 300]}")
end

section "Telegram bot token"
telegram_token = ENV["TELEGRAM_BOT_TOKEN"].to_s
if telegram_token.empty?
  failed "TELEGRAM_BOT_TOKEN not set"
else
  response = http.get("#{VoCinema::Messengers::Telegram::DOMAIN}/bot#{telegram_token}/getMe")
  body     = JSON.parse(response.body) rescue {}
  body["ok"] ? ok("Token valid — bot @#{body.dig("result", "username")}") : failed("HTTP #{response.code}")
end

ENV["TELEGRAM_CHAT_ID"].to_s.empty? ? failed("TELEGRAM_CHAT_ID not set") : ok("TELEGRAM_CHAT_ID set")

# ---------------------------------------------------------------------------
# An empty day is only news if it is a day still to come: the endpoint lists
# what you can still buy a ticket for, so today drains as its programme runs.
section "SensaCine — first cinema, next 7 days"

cinema    = VoCinema::Cinema.all.first
sensacine = VoCinema::Showtimes::Sensacine.new
puts "Cinema: #{cinema.name} (#{cinema.sensacine_id})"

VoCinema::WeeklyNotifier::WEEK_DAYS.times do |offset|
  date     = (VoCinema::Clock.today + offset).to_s
  sessions = sensacine.sessions_for(cinema, date)
  original = sessions.count(&:original_version?)

  puts "  #{date}  #{sessions.length} screening(s), #{original} in original version"
  failed "  #{date} is in the future and empty — that cannot be expiry" if offset.positive? && sessions.empty?
end
