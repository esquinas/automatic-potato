# frozen_string_literal: true

module VoCinema
  module Showtimes
    class Sensacine
      # One day of SensaCine's listing, read as screenings.
      #
      # Nothing here knows how the payload arrived; it is handed the entries
      # and the day they belong to, and answers with ScreeningSessions.
      class Day
        VO_BUCKETS         = %w[original original_st original_sme local local_st local_sme].freeze
        UNFILTERED_BUCKETS = (VO_BUCKETS + %w[dubbed dubbed_st dubbed_sme]).freeze

        def initialize(entries, date)
          @entries = entries
          @date    = date
        end

        def sessions = @entries.flat_map { |entry| screenings_in(entry) }

        private

        def screenings_in(entry)
          film = Film.new(localized_title: title_of(entry), year: year_of(entry))

          UNFILTERED_BUCKETS.flat_map { |bucket| screenings_in_bucket(entry, bucket, film) }
        end

        def screenings_in_bucket(entry, bucket, film)
          (entry.dig("showtimes", bucket) || []).filter_map { |showtime| screening(showtime, bucket, film) }
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

        def title_of(entry) = entry.dig("movie", "title") || "(untitled)"

        # The feed carries the film's own year under movie.data and the dates it
        # reached cinemas under movie.releases[]. The production year is the one
        # TMDB files a film under, so it is the one worth searching by; the
        # earliest release is the fallback for an entry that arrives without one.
        def year_of(entry)
          entry.dig("movie", "data", "productionYear") ||
            earliest_release_year(entry.dig("movie", "releases") || [])
        end

        def earliest_release_year(releases)
          releases.filter_map { |release| release.dig("releaseDate", "date").to_s[/\A\d{4}/] }.min&.to_i
        end
      end
    end
  end
end
