#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "date"

TELEGRAM_BOT_TOKEN = ENV.fetch("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID   = ENV.fetch("TELEGRAM_CHAT_ID")
THEATER_ID         = "E0628"

SENSACINE_HEADERS = {
  "User-Agent"      => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  "Accept"          => "application/json",
  "Accept-Language" => "es-ES,es;q=0.9",
  "Referer"         => "https://www.sensacine.com/cines/cine/#{THEATER_ID}/"
}.freeze

def http_get(url, headers = {})
  uri = URI(url)
  req = Net::HTTP::Get.new(uri, headers)
  Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 10) { |h| h.request(req) }
end

def telegram_send(text)
  uri = URI("https://api.telegram.org/bot#{TELEGRAM_BOT_TOKEN}/sendMessage")
  req = Net::HTTP::Post.new(uri)
  req.content_type = "application/json"
  req.body = JSON.generate(chat_id: TELEGRAM_CHAT_ID, text: text, parse_mode: "HTML")
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
end

date = Date.today.to_s
url  = "https://www.sensacine.com/_/showtimes/theater-#{THEATER_ID}/d-#{date}/p-1/"

puts "GET #{url}"
resp = http_get(url, SENSACINE_HEADERS)
puts "HTTP #{resp.code}"

if resp.code != "200"
  telegram_send("ERROR: SensaCine returned HTTP #{resp.code}")
  exit 1
end

# Truncate to fit Telegram's 4096-char limit (leave room for header)
raw   = JSON.pretty_generate(JSON.parse(resp.body))
limit = 3800
body  = raw.length > limit ? raw[0, limit] + "\n... (truncated)" : raw

telegram_send("<b>SensaCine raw dump (#{date})</b>\n<pre>#{body}</pre>")
puts "Sent #{body.length} chars to Telegram"
