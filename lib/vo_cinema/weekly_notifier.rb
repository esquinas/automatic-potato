# frozen_string_literal: true

require "date"

module VoCinema
  # The orchestrator: collect the week's screenings cinema by cinema, enrich
  # each film with what TMDB knows, hand the result to the renderer, send it.
  #
  # It takes a list of showtimes providers and asks every one of them about
  # every cinema; a provider that does not cover a venue says so by answering
  # with nothing. The order they are given in does not matter — see #merge.
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

    # One screening, however many providers mentioned it — and original version
    # if ANY of them said so.
    #
    # The two claims are not equally reliable. Saying "original version" takes
    # information: a bucket named for it, a diffusionVersion of "ORIGINAL", a
    # VOSE language tag. Saying "dubbed" is what a provider says when it has
    # nothing, which is why SensaCine files Yelmo's subtitled prints that way,
    # and why Yelmo labels a Spanish film "ESPAÑOL" when that print is the
    # original. A negative is an absence of evidence; a positive is evidence.
    #
    # So a dubbed screening can reach the digest on one provider's bad word.
    # That is an accepted cost: the box office says which print it is before
    # anyone pays, and cinemas are far more careful about the opposite mistake
    # — an audience expecting dubbing and getting subtitles complains.
    #
    # Nothing here depends on the order the providers were given in.
    def merge(weeks)
      lend_known_years(weeks)

      weeks.flatten.group_by(&:slot).values.map { |group| agreed(group) }
    end

    # The first record supplies the screening; every record gets a vote on
    # whether it is the original version.
    def agreed(group)
      group.first.with(original_version?: group.any?(&:original_version?))
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
