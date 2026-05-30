# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class TelegramMessenger
  DOMAIN = "https://api.telegram.org"

  def initialize(token: ENV.fetch("TELEGRAM_BOT_TOKEN"), chat_id: ENV.fetch("TELEGRAM_CHAT_ID"))
    @token   = token
    @chat_id = chat_id
  end

  def send_message(text)
    uri = URI("#{DOMAIN}/bot#{@token}/sendMessage")
    req = Net::HTTP::Post.new(uri)
    req.content_type = "application/json"
    req.body = JSON.generate(chat_id: @chat_id, text: text, parse_mode: "HTML")
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  end
end
