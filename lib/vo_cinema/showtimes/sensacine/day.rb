# frozen_string_literal: true

module VoCinema
  module Showtimes
    class Sensacine
      # One day of SensaCine's listing, read as screenings.
      #
      # Nothing here knows how the payload arrived; it is handed the entries
      # and the day they belong to, and answers with ScreeningSessions. Naming
      # the film is Movie's job — this half is only about buckets and the clock.
      class Day
        VO_BUCKETS         = %w[original original_st original_sme local local_st local_sme].freeze
        UNFILTERED_BUCKETS = (VO_BUCKETS + %w[dubbed dubbed_st dubbed_sme]).freeze

        def initialize(entries, date)
          @entries = entries
          @date    = date
        end

        def sessions = @entries.flat_map { |entry| screenings_in(entry) }

        private

        # An entry Movie could not name is dropped: it has nothing to print,
        # look up or match on, whatever times it carries.
        def screenings_in(entry)
          film = Movie.new(entry).film
          return [] unless film

          UNFILTERED_BUCKETS.flat_map { |bucket| screenings_in_bucket(entry, bucket, film) }
        end

        def screenings_in_bucket(entry, bucket, film)
          showtimes = entry.dig("showtimes", bucket) || []

          showtimes.filter_map { |showtime| screening(showtime, bucket, film) }
        end

        # Both signals count. The bucket alone is not enough: SensaCine misfiles
        # some subtitled prints under "dubbed", where only diffusionVersion
        # gives them away — that is how Yelmo's VOSE screenings arrive.
        def screening(showtime, bucket, film)
          starts_at = showtime["startsAt"]&.slice(11, 5)
          return nil unless starts_at

          ScreeningSession.new(
            film: film, date: @date, starts_at: starts_at,
            original_version?: VO_BUCKETS.include?(bucket) || showtime["diffusionVersion"] == "ORIGINAL"
          )
        end
      end
    end
  end
end
