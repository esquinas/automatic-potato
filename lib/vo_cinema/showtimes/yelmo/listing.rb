# frozen_string_literal: true

module VoCinema
  module Showtimes
    class Yelmo
      # One cinema's fortnight as Yelmo publishes it, read as screenings by day.
      #
      # Yelmo nests a day three deep: each film is offered in several formats —
      # dubbed, subtitled, 3D — and each format has its own list of times, so
      # the language tag that decides original_version? belongs to the format
      # rather than to the film.
      class Listing
        VO_LANGUAGES = %w[VOSE SUBTITULAD V.O.S.].freeze

        # Handed nil when the city payload had no such cinema: an absent venue
        # simply has no days.
        def initialize(payload)
          @payload = payload.to_h
        end

        # { "2026-08-29" => [ScreeningSession, ...] }
        def by_date
          (@payload["Dates"] || []).each_with_object({}) do |day, days|
            date       = date_of(day)
            days[date] = sessions_on(day, date)
          end
        end

        private

        def sessions_on(day, date)
          (day["Movies"] || []).flat_map { |movie| screenings_of(movie, date) }
        end

        # A film Movie could not name is dropped, whatever formats it carries.
        def screenings_of(movie, date)
          film = Movie.new(movie).film
          return [] unless film

          formats = movie["Formats"] || []

          formats.flat_map { |format| screenings_in_format(film, date, format) }
        end

        # Every time in one format is the same print of the same film, so the
        # language tag is read once for all of them.
        def screenings_in_format(film, date, format)
          original_version = original_version?(format)

          times_in(format).map do |starts_at|
            ScreeningSession.new(
              film: film, date: date, starts_at: starts_at, original_version?: original_version
            )
          end
        end

        def times_in(format) = (format["Showtimes"] || []).filter_map { |showtime| showtime["Time"]&.slice(0, 5) }

        def original_version?(format)
          language = format["Language"].to_s

          VO_LANGUAGES.any? { |tag| language.include?(tag) }
        end

        # Yelmo dates a day as milliseconds since the epoch, at an hour safely
        # inside it, so the calendar date survives the trip through UTC.
        def date_of(day)
          milliseconds = day["FilterDate"].to_s[/\d+/].to_i

          Time.at(milliseconds / 1000).utc.strftime("%Y-%m-%d")
        end
      end
    end
  end
end
