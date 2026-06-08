# frozen_string_literal: true

require "date"
require_relative "digest_formatter"

class WeeklyNotifier
  WEEK_DAYS    = 7
  CinemaDigest = Data.define(:cinema, :sessions, :ratings)

  def initialize(showtimes:, movies_db:, messenger:, cinemas:, formatter: DigestFormatter.new)
    @showtimes = showtimes
    @movies_db = movies_db
    @messenger = messenger
    @cinemas   = cinemas
    @formatter = formatter
  end

  def run(today: Date.today)
    digests = @cinemas.map { |cinema| build_cinema_digest(cinema, today) }
    @messenger.send_message(@formatter.format(digests, today: today))
  end

  private

  def build_cinema_digest(cinema, today)
    sessions = collect_sessions(cinema, today)
    return CinemaDigest.new(cinema: cinema, sessions: sessions, ratings: {}) if sessions.empty?

    films = sessions.map(&:film).uniq
    films.each { |film| film.title = @movies_db.fetch_original_title(film) }
    ratings = films.to_h { |film| [film, @movies_db.rating_for(film)] }
    CinemaDigest.new(cinema: cinema, sessions: sessions, ratings: ratings)
  end

  def collect_sessions(cinema, today)
    WEEK_DAYS.times.flat_map do |offset|
      date     = (today + offset).to_s
      sessions = @showtimes.fetch_theater_movie_sessions(date: date, theater_id: cinema["id"])
      cinema["check_vo"] ? sessions.select(&:original_version?) : sessions
    end
  end
end
