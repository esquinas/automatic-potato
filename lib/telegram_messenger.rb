# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

# Delivers the digest to the Telegram channel subscribers read.
class TelegramMessenger
  DOMAIN = "https://api.telegram.org"

  def initialize(token: ENV.fetch("TELEGRAM_BOT_TOKEN"), chat_id: ENV.fetch("TELEGRAM_CHAT_ID"))
    @token   = token
    @chat_id = chat_id
  end

  def send_message(text)
    uri = URI("#{DOMAIN}/bot#{@token}/sendMessage")
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |connection| connection.request(post_to(uri, text)) }
  end

  private

  def post_to(uri, text)
    request              = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request.body         = JSON.generate(chat_id: @chat_id, text: text, parse_mode: "HTML")
    request
  end
end
