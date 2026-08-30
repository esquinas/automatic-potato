# frozen_string_literal: true

module VoCinema
  module Messengers
    # Delivers the digest to the terminal, for developing without a Telegram token.
    #
    # The digest is written in the markup Telegram wants, which is noise anywhere
    # else: every heading arrives wrapped in <b>, every showtime in <pre>. A
    # messenger is responsible for its own medium, so this one takes the markup
    # back off rather than asking the renderer to produce a second flavour.
    class Stdout
      MARKUP = /<[^>]+>/

      def initialize(**) = nil

      def send_message(text)
        puts text.gsub(MARKUP, "")
      end
    end
  end
end
