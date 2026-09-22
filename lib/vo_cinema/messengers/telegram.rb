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

      # The digest is written as blocks set off by a blank line — a cinema
      # heading, or one film with its timetable — and every tag and entity
      # opens and closes inside its block. Cutting between blocks is what keeps
      # a shortened digest valid HTML: a cut inside <pre> or through an &amp;
      # makes Telegram reject the lot, which is the very thing the limit is for.
      BLOCK_BREAK = "\n\n"
      TRUNCATED   = "... (truncated)"

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

        "#{whole_blocks_of(text) || plain_head_of(text)}#{BLOCK_BREAK}#{TRUNCATED}"
      end

      def whole_blocks_of(text)
        cut = text.rindex(BLOCK_BREAK, MAX_MSG_CHARS)
        cut&.positive? ? text[0, cut] : nil
      end

      # Only reached if a single block outgrows the limit, which no real week
      # comes near. Without its markup the head cannot hold a half-open tag;
      # an entity the cut went through is dropped rather than sent broken.
      def plain_head_of(text)
        text[0, MAX_MSG_CHARS].gsub(/<[^>]*>?/, "").sub(/&[^;\s]*\z/, "")
      end
    end
  end
end
