# frozen_string_literal: true

module VoCinema
  module Showtimes
    class Sensacine
      # The `movie` half of one SensaCine listing entry, read as a Film.
      #
      # Three different corners of the payload have to be understood to name a
      # film: the title, the year (which lives in two places), and the director
      # (buried in a flat credit list). None of that has anything to do with
      # showtimes, buckets or the clock, which is what Day is left with.
      class Movie
        DIRECTOR = "DIRECTOR"

        def initialize(entry)
          @movie = entry["movie"] || {}
        end

        # An entry the feed does not name is not a film. It used to become one
        # called "(untitled)", which TMDB answered with "Untitled Immaculate
        # Reception Film" — so a concert reached the digest under a stranger's
        # name. There is nothing to print, look up or match on; where another
        # provider covers the same screening it arrives from there properly
        # named, as the André Rieu concert at Ocimax does.
        def film
          return nil if title.empty?

          Film.new(localized_title: title, year: year, director: director)
        end

        private

        def title = @movie["title"].to_s.strip

        # The feed carries the film's own year under movie.data and the dates it
        # reached cinemas under movie.releases[]. The production year is the one
        # TMDB files a film under, so it is the one worth searching by; the
        # earliest release is the fallback for an entry that arrives without one.
        def year = @movie.dig("data", "productionYear") || earliest_release_year

        def earliest_release_year
          releases = @movie["releases"] || []

          releases.filter_map { |release| release.dig("releaseDate", "date").to_s[/\A\d{4}/] }.min&.to_i
        end

        # The credits are a flat list of everyone who worked on the film, each
        # tagged with the job they did. The director is the one worth reading,
        # because Yelmo publishes one too and it is what lets a film billed two
        # different ways be matched.
        def director
          name = "#{credited["firstName"]} #{credited["lastName"]}".strip

          name.empty? ? nil : name
        end

        def credited
          credits = @movie["credits"] || []

          credits.find { |credit| credit.dig("position", "name") == DIRECTOR }&.dig("person") || {}
        end
      end
    end
  end
end
