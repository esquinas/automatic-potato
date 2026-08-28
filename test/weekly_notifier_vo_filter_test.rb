# frozen_string_literal: true

require "date"
require_relative "../lib/weekly_notifier"

# Which screenings survive to reach a subscriber.
#
# Gijón's municipal venues and the Laboral programme in original version as a
# matter of policy, so nothing needs filtering there. The commercial cinemas
# mostly dub, so their listings are filtered — and that filter has one
# exception that took a while to find.
class WeeklyNotifierVoFilterTest < ServiceTest
  include Screenings

  MONDAY = Date.new(2026, 8, 31)

  COMMERCIAL_CINEMA = {
    "name" => "Ocine Premium Los Fresnos", "id" => "E2907",
    "url" => "https://www.ocinepremiumlosfresnos.es/", "check_vo" => true
  }.freeze

  # No check_vo key at all: everything this venue screens is worth listing.
  ORIGINAL_VERSION_ONLY_VENUE = {
    "name" => "Centro de Cultura Antiguo Instituto", "id" => "G02E9",
    "url" => "https://www.gijon.es/es/directorio/centro-de-cultura-antiguo-instituto"
  }.freeze

  def test_at_a_cinema_that_dubs_only_the_original_version_screenings_are_listed
    dog_stars = film("La constelación del perro", year: 2026)
    listings  = Listings.new("E2907" => [
      screening(dog_stars, on: "2026-09-04", at: "18:45", original_version: false),
      screening(dog_stars, on: "2026-09-04", at: "21:15", original_version: true)
    ])
    outbox = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: MovieDatabase.new,
                       messenger: outbox, cinemas: [COMMERCIAL_CINEMA]).run(today: MONDAY)

    assert_equal ["21:15"], outbox.digest.times_listed_for("La constelación del perro")
  end

  def test_at_a_venue_that_only_ever_screens_in_original_version_nothing_is_filtered
    # These venues carry no check_vo flag: a provider that reports their
    # screenings as "dubbed" is simply wrong about them, and filtering on that
    # would empty the section.
    obscure  = film("Ciclo Buñuel: presentación")
    listings = Listings.new("G02E9" => [
      screening(obscure, on: "2026-09-04", at: "20:00", original_version: false)
    ])
    outbox = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: MovieDatabase.new,
                       messenger: outbox, cinemas: [ORIGINAL_VERSION_ONLY_VENUE]).run(today: MONDAY)

    assert outbox.digest.mentions?("Ciclo Buñuel: presentación")
  end

  def test_a_spanish_production_survives_the_filter_even_though_nobody_tagged_it
    # The exception. A Spanish film is never dubbed and never subtitled, so no
    # provider ever marks it as a version of anything — its only print simply
    # is the original. TMDB's original_language is the only way to tell that
    # apart from a foreign film dubbed into Spanish.
    querido  = film("El ser querido", year: 2026)
    listings = Listings.new("E2907" => [
      screening(querido, on: "2026-09-04", at: "19:00", original_version: false)
    ])
    tmdb   = MovieDatabase.new(spanish_productions: ["El ser querido"])
    outbox = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: tmdb,
                       messenger: outbox, cinemas: [COMMERCIAL_CINEMA]).run(today: MONDAY)

    assert_equal ["19:00"], outbox.digest.times_listed_for("El ser querido")
  end

  def test_a_foreign_film_dubbed_into_spanish_is_still_dropped
    dog_stars = film("La constelación del perro", year: 2026)
    listings  = Listings.new("E2907" => [
      screening(dog_stars, on: "2026-09-04", at: "18:45", original_version: false)
    ])
    outbox = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: MovieDatabase.new,
                       messenger: outbox, cinemas: [COMMERCIAL_CINEMA]).run(today: MONDAY)

    refute outbox.digest.mentions?("La constelación del perro")
    assert outbox.digest.mentions?("no VO sessions")
  end

  def test_tmdb_is_asked_about_a_film_once_however_often_it_screens
    # Fourteen screenings of the same film is fourteen chances to ask TMDB the
    # same question. The answer is remembered for the length of the run.
    querido      = film("El ser querido", year: 2026)
    all_week     = (0..6).flat_map do |offset|
      day = (MONDAY + offset).to_s
      [screening(querido, on: day, at: "19:00", original_version: false),
       screening(querido, on: day, at: "21:30", original_version: false)]
    end
    tmdb = MovieDatabase.new(spanish_productions: ["El ser querido"])

    WeeklyNotifier.new(showtimes: Listings.new("E2907" => all_week), movies_db: tmdb,
                       messenger: Outbox.new, cinemas: [COMMERCIAL_CINEMA]).run(today: MONDAY)

    assert_equal 1, tmdb.times_asked(:spanish_original?, "El ser querido")
  end

  def test_a_screening_already_known_to_be_in_original_version_costs_no_tmdb_call
    dog_stars = film("La constelación del perro", year: 2026)
    listings  = Listings.new("E2907" => [
      screening(dog_stars, on: "2026-09-04", at: "21:15", original_version: true)
    ])
    tmdb = MovieDatabase.new

    WeeklyNotifier.new(showtimes: listings, movies_db: tmdb,
                       messenger: Outbox.new, cinemas: [COMMERCIAL_CINEMA]).run(today: MONDAY)

    assert_equal 0, tmdb.times_asked(:spanish_original?, "La constelación del perro")
  end
end
