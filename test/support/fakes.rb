# frozen_string_literal: true

# Stand-ins for the notifier's collaborators.
#
# These are small real objects rather than strict mocks on purpose. A mock that
# expects two calls in a fixed order fails when the notifier is reorganised
# even though the digest it produces is identical — exactly the brittleness
# this suite is trying to avoid. These answer any question, any number of
# times, in any order, and write down what they were asked so that a test which
# genuinely cares about the number of calls can say so out loud.

# A showtimes provider whose week is already known, keyed by cinema name.
# Sessions carry their own date, so it hands back the ones belonging to the day
# being asked about — and nothing at all for a venue it was told nothing about,
# which is how a real provider says it does not cover a cinema.
class Listings
  def initialize(sessions_by_cinema)
    @sessions_by_cinema = sessions_by_cinema
    @days_asked_about   = []
    @name               = "Listings"
  end

  # Two providers in one test have to answer to different names, or the
  # agreement report cannot tell which of them said what — and counts a
  # screening they both described as covered by one voice.
  def self.named(name, sessions_by_cinema)
    new(sessions_by_cinema).tap { |listings| listings.name = name }
  end

  attr_reader :days_asked_about
  attr_accessor :name

  def sessions_for(cinema, date)
    @days_asked_about << [cinema.name, date]
    @sessions_by_cinema.fetch(cinema.name, []).select { |session| session.date == date }
  end
end

# A stand-in for TMDB that has been told about a handful of films, keyed by the
# Spanish title the cinemas use. Anything it has not been told about behaves
# like a film TMDB could not match.
class MovieDatabase
  def initialize(original_titles: {}, ratings: {}, spanish_productions: [])
    @original_titles     = original_titles
    @ratings             = ratings
    @spanish_productions = spanish_productions
    @questions           = []
  end

  attr_reader :questions

  def fetch_original_title(film)
    @questions << [:fetch_original_title, film.localized_title]
    @original_titles[film.localized_title]
  end

  def rating_for(film)
    @questions << [:rating_for, film.localized_title]
    @ratings.fetch(film.localized_title, VoCinema::Rating.null)
  end

  def spanish_original?(film)
    @questions << [:spanish_original?, film.localized_title]
    @spanish_productions.include?(film.localized_title)
  end

  def times_asked(question, title)
    questions.count([question, title])
  end
end

# Keeps the digest instead of posting it anywhere.
class Outbox
  def initialize
    @messages = []
  end

  attr_reader :messages

  def send_message(text)
    @messages << text
  end

  # The digest, ready to be read. Fails loudly if the run sent none, or more
  # than one — a subscriber getting two half-digests would be a real bug.
  def digest
    raise "Nothing was sent" if messages.empty?
    raise "Expected one message, got #{messages.length}" if messages.length > 1

    RenderedDigest.new(messages.first)
  end
end

# Builds the domain objects a test needs, the way the real thing would.
module Screenings
  def screening(film, on:, at:, original_version: true)
    VoCinema::ScreeningSession.new(film: film, date: on, starts_at: at, original_version?: original_version)
  end

  def film(localized_title, year: nil, director: nil)
    VoCinema::Film.new(localized_title: localized_title, year: year, director: director)
  end

  def cinema(name, sensacine_id: nil, yelmo_id: nil, url: nil, check_vo: false)
    VoCinema::Cinema.new(
      name: name, url: url, sensacine_id: sensacine_id, yelmo_id: yelmo_id, check_vo: check_vo
    )
  end
end
