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

        def initialize(payload)
          @payload = payload || {}
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

        # A film the payload does not name is dropped, for the same reason
        # SensaCine's untitled entries are: there is nothing to print, look up
        # or match on. See Sensacine::Day#screenings_in.
        def screenings_of(movie, date)
          title = movie["Title"].to_s
          return [] if title.strip.empty?

          film = Film.new(localized_title: title, year: nil, director: director_of(movie))

          (movie["Formats"] || []).flat_map { |format| screenings_in_format(film, date, format) }
        end

        # A film is offered in several formats and each has its own list of
        # times, so one film's day is two levels deep.
        def screenings_in_format(film, date, format)
          times_in(format).map { |time| screening(film, date, time, format) }
        end

        # Yelmo pads some names with a double space ("Will  Gluck"), which is
        # why Film compares directors squeezed rather than as written.
        def director_of(movie)
          name = movie["Director"].to_s.strip

          name.empty? ? nil : name
        end

        def times_in(format) = (format["Showtimes"] || []).filter_map { |showtime| showtime["Time"]&.slice(0, 5) }

        def screening(film, date, starts_at, format)
          ScreeningSession.new(
            film: film, date: date, starts_at: starts_at, original_version?: original_version?(format)
          )
        end

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
