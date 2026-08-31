# frozen_string_literal: true

require "date"

module VoCinema
  # The orchestrator: collect the week's screenings cinema by cinema, enrich
  # each film with what TMDB knows, hand the result to the renderer, send it.
  #
  # It takes a list of showtimes providers and asks every one of them about
  # every cinema; a provider that does not cover a venue says so by answering
  # with nothing. The order they are given in does not matter — Reconciliation
  # unions their claims rather than letting the last one win.
  class WeeklyNotifier
    WEEK_DAYS = 7

    def initialize(showtimes:, movies_db:, messenger:, cinemas:)
      @showtimes = Array(showtimes)
      @movies_db = movies_db
      @messenger = messenger
      @cinemas   = cinemas
    end

    def run(today: Date.today)
      weeks = @cinemas.map { |cinema| [cinema, Reconciliation.new(week_at(cinema, today))] }

      report_agreement(weeks, today)
      deliver(digest_of(weeks, today))
    end

    private

    def digest_of(weeks, today)
      programmes            = weeks.map { |cinema, week| [cinema, surviving(cinema, week.sessions)] }
      showing, nothing_left = programmes.partition { |_cinema, sessions| sessions.any? }
      listings              = showing.map { |cinema, sessions| listing_for(cinema, sessions) }

      Digest::Renderer.new(today: today, week_days: WEEK_DAYS)
                      .render(listings, nothing_left.map { |cinema, _| cinema.name })
    end

    def deliver(message)
      @messenger.send_message(message)
      puts "Sent #{message.length} chars"
    end

    # Provider health goes in the run log and never in the digest. Silent when
    # no venue had two providers to compare — that is not a finding.
    def report_agreement(weeks, today)
      health = AgreementReport.new(weeks.map { |cinema, week| [cinema, week.agreement] }, today).to_s

      puts health unless health.empty?
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

    # Every provider is asked about every cinema, and answers for itself. Its
    # name comes along so the agreement report can say which of them said what.
    def week_at(cinema, today)
      @showtimes.map { |provider| [provider.name, week_from(provider, cinema, today)] }
    end

    def week_from(provider, cinema, today)
      WEEK_DAYS.times.flat_map { |offset| provider.sessions_for(cinema, (today + offset).to_s) }
    end

    def surviving(cinema, sessions)
      return sessions unless cinema.check_vo

      # A film with no dubbed/subtitled distinction (e.g. a Spanish production)
      # never gets tagged VO by a provider, since there is nothing to dub or
      # subtitle — its only screening IS the original version. TMDB's
      # original_language is the only way to tell that apart from a foreign
      # film dubbed into Spanish. Asked once per screening and answered from
      # the movie database's own cache, not one kept here.
      sessions.select { |session| session.original_version? || @movies_db.spanish_original?(session.film) }
    end
  end
end
