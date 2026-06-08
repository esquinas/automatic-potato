# frozen_string_literal: true

require_relative "../film"
require_relative "../screening_session"

module Parsers
  class SensacineSessionParser
    VO_BUCKETS = %w[original local].freeze
    UNFILTERED_BUCKETS = %w[original local dubbed].freeze

    def parse(results, date)
      results.flat_map do |entry|
        film = Film.new(
          localized_title: entry.dig("movie", "title") || "(untitled)",
          year:            entry.dig("movie", "release", "year")
        )

        UNFILTERED_BUCKETS.flat_map do |bucket|
          original_version = VO_BUCKETS.include?(bucket)

          (entry.dig("showtimes", bucket) || []).filter_map do |showtime|
            starts_at = showtime["startsAt"]&.slice(11, 5)
            next unless starts_at

            ScreeningSession.new(
              film:              film,
              date:              date,
              starts_at:         starts_at,
              original_version?: original_version
            )
          end
        end
      end
    end
  end
end
