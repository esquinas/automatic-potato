#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

TELEGRAM_BOT_TOKEN = ENV.fetch("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID   = ENV.fetch("TELEGRAM_CHAT_ID")

def telegram_send(text)
  uri = URI("https://api.telegram.org/bot#{TELEGRAM_BOT_TOKEN}/sendMessage")
  req = Net::HTTP::Post.new(uri)
  req.content_type = "application/json"
  req.body = JSON.generate(chat_id: TELEGRAM_CHAT_ID, text: text)
  Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
end

resp = telegram_send("Hello from Gijón VO bot!")
puts "Telegram response: #{resp.code} #{resp.body}"
