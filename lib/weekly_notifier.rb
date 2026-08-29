# frozen_string_literal: true

require "date"
require_relative "cinema_listing"
require_relative "digest_renderer"

# The orchestrator: collect the week's screenings cinema by cinema, enrich each
# film with what TMDB knows, hand the result to the renderer, and send it.
#
# Everything about how the message *looks* lives in DigestRenderer. What stays
# here is the part that talks to other things.
class WeeklyNotifier
  WEEK_DAYS = 7

  def initialize(showtimes:, movies_db:, messenger:, cinemas:, yelmo_showtimes: nil)
    @showtimes       = showtimes
    @movies_db       = movies_db
    @messenger       = messenger
    @cinemas         = cinemas
    @yelmo_showtimes = yelmo_showtimes
  end

  def run(today: Date.today)
    listings        = []
    nothing_left_at = []

    @cinemas.each do |cinema|
      sessions = collect_sessions(cinema, today)
      sessions.empty? ? nothing_left_at << cinema["name"] : listings << listing_for(cinema, sessions)
    end

    message = DigestRenderer.new(today: today, week_days: WEEK_DAYS).render(listings, nothing_left_at)

    @messenger.send_message(message)
    puts "Sent #{message.length} chars"
  end

  private

  # The providers only know a film by its Spanish release title. Filling in the
  # original title and the rating happens here, before anything is rendered,
  # because this object owns the enrichment lifecycle — TmdbClient stays a pure
  # query and the renderer stays a pure function.
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
    sessions = week_from(@showtimes, cinema["id"], today)
    sessions = merge_sessions(sessions, week_from(@yelmo_showtimes, cinema["yelmo_id"], today)) if yelmo_runs?(cinema)

    return sessions unless cinema["check_vo"]

    sessions.select { |session| session.original_version? || spanish_original?(session.film) }
  end

  def week_from(provider, theater_id, today)
    WEEK_DAYS.times.flat_map do |offset|
      provider.fetch_theater_movie_sessions(date: (today + offset).to_s, theater_id: theater_id)
    end
  end

  def yelmo_runs?(cinema) = @yelmo_showtimes && cinema["yelmo_id"]

  # A film with no dubbed/subtitled distinction (e.g. a Spanish production) never
  # gets tagged VO by a provider, since there's nothing to dub or subtitle — its
  # only screening IS the original version. TMDB's original_language is the only
  # way to tell that apart from a foreign film dubbed into Spanish.
  def spanish_original?(film)
    @spanish_original_cache ||= {}
    @spanish_original_cache.fetch(film) { @spanish_original_cache[film] = @movies_db.spanish_original?(film) }
  end

  # Where two providers describe the same slot, the one that calls it original
  # version wins: SensaCine files Yelmo's subtitled screenings under "dubbed".
  def merge_sessions(primary, secondary)
    lend_known_years(from: primary, to: secondary)

    (primary + secondary)
      .group_by { |session| [session.date, session.starts_at, title_key(session.film)] }
      .values
      .map { |group| group.find(&:original_version?) || group.first }
  end

  # Only SensaCine reports a year, and a Film is only the same film when the
  # year matches too. Without this, Yelmo's copy of a film both providers list
  # reaches the digest as a second, yearless film of the same name — printed
  # twice, with the week's showtimes split between the two entries.
  def lend_known_years(from:, to:)
    years = from.map(&:film).to_h { |film| [title_key(film), film.year] }
    to.map(&:film).each { |film| film.year ||= years[title_key(film)] }
  end

  def title_key(film) = film.localized_title.downcase.strip
end
