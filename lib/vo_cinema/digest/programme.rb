# frozen_string_literal: true

module VoCinema
  module Digest
    # The week's programme, ready to be rendered: one CinemaListing per venue
    # that still has something to show, and the names of the venues that do not.
    #
    # This is the one place TMDB is asked what it knows. A film is not ready to
    # print until its original title and rating are filled in, and at the venues
    # that filter, TMDB's answer to "was this made in Spanish?" is what keeps a
    # Spanish film's only print from being taken for a dub.
    #
    # So the enrichment lives between the two halves that must not know about
    # it: upstream the providers never hear of TMDB, and downstream Renderer
    # stays a pure function of what comes out of here.
    class Programme
      def initialize(weeks, movies_db:)
        @weeks     = weeks
        @movies_db = movies_db
      end

      def listings
        venues_still_showing.map { |cinema, sessions| listing_for(cinema, sessions) }
      end

      def venues_with_nothing_left
        venues_showing_nothing.map { |cinema, _sessions| cinema.name }
      end

      private

      def venues_still_showing  = filtered_weeks.first
      def venues_showing_nothing = filtered_weeks.last

      # Worked out once: deciding what survives asks TMDB about films, and both
      # public queries are answered from the same split.
      def filtered_weeks
        @filtered_weeks ||= @weeks.map { |cinema, week| [cinema, worth_listing(cinema, week.sessions)] }
                                  .partition { |_cinema, sessions| sessions.any? }
      end

      def worth_listing(cinema, sessions)
        return sessions unless cinema.check_vo

        sessions.select { |session| in_the_original_language?(session) }
      end

      # A film with no dubbed/subtitled distinction (e.g. a Spanish production)
      # never gets tagged VO by a provider, since there is nothing to dub or
      # subtitle — its only screening IS the original version. TMDB's
      # original_language is the only way to tell that apart from a foreign film
      # dubbed into Spanish. Asked once per screening and answered from the
      # movie database's own cache, not one kept here.
      def in_the_original_language?(session)
        session.original_version? || @movies_db.spanish_original?(session.film)
      end

      # The providers only know a film by its Spanish release title, so the
      # original title and the rating are filled in here, before anything is
      # rendered.
      #
      # Order matters: the rating is looked up by the original title once it is
      # known, so the titles are filled in first.
      def listing_for(cinema, sessions)
        films = sessions.map(&:film).uniq
        films.each { |film| film.title = @movies_db.fetch_original_title(film) }

        CinemaListing.new(cinema: cinema, sessions: sessions, ratings: ratings_for(films))
      end

      def ratings_for(films) = films.to_h { |film| [film, @movies_db.rating_for(film)] }
    end
  end
end
