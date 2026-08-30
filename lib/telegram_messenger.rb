# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

# Delivers the digest to the Telegram channel subscribers read.
class TelegramMessenger
  DOMAIN = "https://api.telegram.org"

  # Telegram rejects anything past 4096 characters outright, which would cost
  # the whole digest rather than its tail. The limit belongs here rather than
  # in the renderer: it is a fact about this channel, and the renderer has no
  # idea where its text is going. Sending the same digest to a terminal should
  # not cut it short.
  MAX_MSG_CHARS = 3800

  def initialize(token: ENV.fetch("TELEGRAM_BOT_TOKEN"), chat_id: ENV.fetch("TELEGRAM_CHAT_ID"))
    @token   = token
    @chat_id = chat_id
  end

  def send_message(text)
    uri = URI("#{DOMAIN}/bot#{@token}/sendMessage")
    body = within_limit(text)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |connection| connection.request(post_to(uri, body)) }
  end

  private

  def within_limit(text)
    return text if text.length <= MAX_MSG_CHARS

    "#{text[0, MAX_MSG_CHARS]}\n... (truncated)"
  end

  def post_to(uri, text)
    request              = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request.body         = JSON.generate(chat_id: @chat_id, text: text, parse_mode: "HTML")
    request
  end
end
