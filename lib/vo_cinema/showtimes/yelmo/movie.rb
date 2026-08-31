# frozen_string_literal: true

module VoCinema
  module Showtimes
    class Yelmo
      # One film as Yelmo names it, read as a Film.
      #
      # The counterpart of Sensacine::Movie: both providers publish a title and
      # a director, and reading them is a separate job from reading the formats
      # and clock times wrapped around them, which is what Listing keeps.
      #
      # Yelmo dates nothing — no year reaches a Film from here. Reconciliation
      # lends one from SensaCine where both describe the same film.
      class Movie
        def initialize(movie)
          @movie = movie.to_h
        end

        # A film the payload does not name is not a film, for the same reason
        # SensaCine's unnamed entries are not: nothing to print, look up at
        # TMDB, or match the other provider on.
        def film
          return nil if title.empty?

          Film.new(localized_title: title, year: nil, director: director)
        end

        private

        def title = @movie["Title"].to_s.strip

        # Yelmo pads some names with a double space ("Will  Gluck"), which is
        # why Film compares directors squeezed rather than as written.
        def director
          name = @movie["Director"].to_s.strip

          name.empty? ? nil : name
        end
      end
    end
  end
end
