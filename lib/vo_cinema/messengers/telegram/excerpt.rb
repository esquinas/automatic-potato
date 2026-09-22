# frozen_string_literal: true

module VoCinema
  module Messengers
    class Telegram
      # As much of a digest as fits in one message, cut where Telegram can still
      # parse what is left.
      #
      # The digest is written as blocks set off by a blank line — a cinema
      # heading, or one film with its timetable — and every tag and entity opens
      # and closes inside its block. Cutting between blocks is what keeps a
      # shortened digest valid HTML: a cut inside <pre> or through an &amp; makes
      # Telegram reject the lot, which is the very thing the limit is for.
      class Excerpt
        BLOCK_BREAK = "\n\n"
        TRUNCATED   = "... (truncated)"

        def initialize(text, limit:)
          @text  = text
          @limit = limit
        end

        def to_s
          return @text if @text.length <= @limit

          "#{whole_blocks || plain_head}#{BLOCK_BREAK}#{TRUNCATED}"
        end

        private

        def whole_blocks
          cut = @text.rindex(BLOCK_BREAK, @limit)
          cut&.positive? ? @text[0, cut] : nil
        end

        # Only reached if a single block outgrows the limit, which no real week
        # comes near. Without its markup the head cannot hold a half-open tag;
        # an entity the cut went through is dropped rather than sent broken.
        def plain_head
          @text[0, @limit].gsub(/<[^>]*>?/, "").sub(/&[^;\s]*\z/, "")
        end
      end
    end
  end
end
