#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "date"
require "yaml"

TELEGRAM_BOT_TOKEN     = ENV.fetch("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID       = ENV.fetch("TELEGRAM_CHAT_ID")
TELEGRAM_MAX_MSG_CHARS = 3800
VO_BUCKETS             = %w[original local].freeze

CINEMAS = YAML.load_file(File.join(__dir__, "..", "config", "cinemas.yml"))["cinemas"].freeze

SENSACINE_HEADERS = {
  "User-Agent"      => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  "Accept"          => "application/json",
  "Accept-Language" => "es-ES,es;q=0.9",
  "Referer"         => "https://www.sensacine.com/cines/cine/"
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

date  = Date.today.to_s
lines = []

CINEMAS.each do |cinema|
  theater_id = cinema["id"]
  url = "https://www.sensacine.com/_/showtimes/theater-#{theater_id}/d-#{date}/p-1/"

  puts "GET #{url}"
  resp = http_get(url, SENSACINE_HEADERS)
  puts "HTTP #{resp.code}"

  if resp.code != "200"
    telegram_send("ERROR: SensaCine returned HTTP #{resp.code} for #{cinema["name"]}")
    exit 1
  end

  results = JSON.parse(resp.body)["results"] || []

  lines << "<b>#{cinema["name"]} — #{date}</b>"

  results.each do |entry|
    title = entry.dig("movie", "title") || "(sin título)"

    times_by_bucket = {}
    VO_BUCKETS.each do |bucket|
      sessions = entry.dig("showtimes", bucket) || []
      next if sessions.empty?

      times = sessions.map { |s| s["startsAt"]&.slice(11, 5) }.compact.sort
      times_by_bucket[bucket] = times
    end

    next if times_by_bucket.empty?

    lines << ""
    lines << "<b>#{title}</b>"
    times_by_bucket.each do |bucket, times|
      lines << "  [#{bucket}] #{times.join(", ")}"
    end
  end

  lines << ""
end

message = lines.join("\n").strip
message = message[0, TELEGRAM_MAX_MSG_CHARS] + "\n... (truncated)" if message.length > TELEGRAM_MAX_MSG_CHARS

telegram_send(message)
puts "Sent #{message.length} chars to Telegram"
