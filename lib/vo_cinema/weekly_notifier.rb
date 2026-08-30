# frozen_string_literal: true

require "date"

module VoCinema
  # The orchestrator: collect the week's screenings cinema by cinema, enrich
  # each film with what TMDB knows, hand the result to the renderer, send it.
  #
  # It takes an ordered list of showtimes providers and asks every one of them
  # about every cinema; a provider that does not cover a venue says so by
  # answering with nothing. Where two describe the same screening the later one
  # is believed, so the list runs from least to most authoritative — SensaCine
  # first, then Yelmo, which is right about its own cinema and which SensaCine
  # systematically misfiles.
  class WeeklyNotifier
    WEEK_DAYS = 7

    def initialize(showtimes:, movies_db:, messenger:, cinemas:)
      @showtimes              = Array(showtimes)
      @movies_db              = movies_db
      @messenger              = messenger
      @cinemas                = cinemas
      @spanish_original_cache = {}
    end

    def run(today: Date.today)
      programmes            = @cinemas.map { |cinema| [cinema, collect_sessions(cinema, today)] }
      showing, nothing_left = programmes.partition { |_cinema, sessions| sessions.any? }
      listings              = showing.map { |cinema, sessions| listing_for(cinema, sessions) }

      deliver(Digest::Renderer.new(today: today, week_days: WEEK_DAYS)
                              .render(listings, nothing_left.map { |cinema, _| cinema.name }))
    end

    private

    def deliver(message)
      @messenger.send_message(message)
      puts "Sent #{message.length} chars"
    end

    # The providers only know a film by its Spanish release title. Filling in
    # the original title and the rating happens here, before anything is
    # rendered, because this object owns the enrichment lifecycle — the movie
    # database stays a pure query and the renderer stays a pure function.
    #
    # Order matters: the rating is looked up by the original title once it is
    # known, so the titles are filled in first.
    def listing_for(cinema, sessions)
      films = sessions.map(&:film).uniq
      films.each { |film| film.title = @movies_db.fetch_original_title(film) }

      CinemaListing.new(
        cinema:   cinema,
        sessions: sessions,
        ratings:  films.to_h { |film| [film, @movies_db.rating_for(film)] }
      )
    end

    def collect_sessions(cinema, today)
      sessions = merge(@showtimes.map { |provider| week_from(provider, cinema, today) })

      return sessions unless cinema.check_vo

      sessions.select { |session| session.original_version? || spanish_original?(session.film) }
    end

    def week_from(provider, cinema, today)
      WEEK_DAYS.times.flat_map { |offset| provider.sessions_for(cinema, (today + offset).to_s) }
    end

    # Providers are listed least to most authoritative, so where several
    # describe the same slot the last word wins.
    def merge(weeks)
      lend_known_years(weeks)

      weeks.flatten.group_by(&:slot).values.map(&:last)
    end

    # Only SensaCine reports a year, and a Film is only the same film when the
    # year matches too. Without this, Yelmo's copy of a film both providers
    # list reaches the digest as a second, yearless film of the same name —
    # printed twice, with the week's showtimes split between the two entries.
    def lend_known_years(weeks)
      films = weeks.flatten.map(&:film)
      years = years_known_for(films)

      films.each { |film| film.year ||= years[film.key] }
    end

    def years_known_for(films) = films.filter_map { |film| [film.key, film.year] if film.year }.to_h

    # A film with no dubbed/subtitled distinction (e.g. a Spanish production)
    # never gets tagged VO by a provider, since there's nothing to dub or
    # subtitle — its only screening IS the original version. TMDB's
    # original_language is the only way to tell that apart from a foreign film
    # dubbed into Spanish.
    def spanish_original?(film)
      @spanish_original_cache.fetch(film) { @spanish_original_cache[film] = @movies_db.spanish_original?(film) }
    end
  end
end
