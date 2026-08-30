# frozen_string_literal: true

require "json"

module VoCinema
  module Messengers
    # Delivers the digest to the Telegram channel subscribers read.
    class Telegram
      DOMAIN  = "https://api.telegram.org"
      HEADERS = { "Content-Type" => "application/json" }.freeze

      # Telegram rejects anything past 4096 characters outright, which would cost
      # the whole digest rather than its tail. The limit belongs here rather than
      # in the renderer: it is a fact about this channel, and the renderer has no
      # idea where its text is going. Sending the same digest to a terminal should
      # not cut it short.
      MAX_MSG_CHARS = 3800

      def initialize(token: ENV.fetch("TELEGRAM_BOT_TOKEN"), chat_id: ENV.fetch("TELEGRAM_CHAT_ID"),
                     http: Http::Client.new(headers: HEADERS))
        @token   = token
        @chat_id = chat_id
        @http    = http
      end

      def send_message(text)
        @http.post("#{DOMAIN}/bot#{@token}/sendMessage", payload_for(within_limit(text)))
      end

      private

      def payload_for(text) = JSON.generate(chat_id: @chat_id, text: text, parse_mode: "HTML")

      def within_limit(text)
        return text if text.length <= MAX_MSG_CHARS

        "#{text[0, MAX_MSG_CHARS]}\n... (truncated)"
      end
    end
  end
end
