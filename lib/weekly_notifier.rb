# frozen_string_literal: true

require "date"
require_relative "weekly_digest"

class WeeklyNotifier
  WEEK_DAYS = 7

  def initialize(showtimes:, movies_db:, formatter:, messenger:, cinemas:)
    @showtimes = showtimes
    @movies_db = movies_db
    @formatter = formatter
    @messenger = messenger
    @cinemas   = cinemas
  end

  def run(today: Date.today)
    message = @formatter.render(digest_for(today))
    @messenger.send_message(message)
    puts "Sent #{message.length} chars"
  end

  private

  def digest_for(today)
    showing, quiet = @cinemas
      .map { |cinema| [cinema, week_sessions(cinema, today)] }
      .partition { |_cinema, sessions| sessions.any? }

    WeeklyDigest.new(
      from:          today,
      to:            today + WEEK_DAYS - 1,
      programs:      showing.map { |cinema, sessions| program_for(cinema, sessions) },
      quiet_cinemas: quiet.map { |cinema, _sessions| cinema.name }
    )
  end

  def week_sessions(cinema, today)
    sessions = WEEK_DAYS.times.flat_map do |offset|
      @showtimes.fetch_theater_movie_sessions(date: (today + offset).to_s, theater_id: cinema.id)
    end
    cinema.check_vo? ? sessions.select(&:original_version?) : sessions
  end

  def program_for(cinema, sessions)
    listings = sessions.map(&:film).uniq.map do |film|
      film.title = @movies_db.fetch_original_title(film)
      FilmListing.new(
        film:     film,
        rating:   @movies_db.rating_for(film),
        sessions: sessions.select { |session| session.film == film }
      )
    end
    CinemaProgram.new(cinema: cinema, listings: listings)
  end
end
