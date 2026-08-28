# frozen_string_literal: true

require "date"
require_relative "../lib/weekly_notifier"

# Yelmo Ocimax is listed by both providers and only one of them is right.
#
# SensaCine files Yelmo's subtitled screenings under "dubbed" alongside the
# Spanish ones, which used to empty the section for the venue most likely to
# have something worth seeing. So for any cinema configured with a yelmo_id the
# notifier reads both sources and merges them, and where they disagree about a
# screening the one that calls it original version wins.
class WeeklyNotifierYelmoMergeTest < ServiceTest
  include Screenings

  MONDAY = Date.new(2026, 8, 31)

  OCIMAX = {
    "name"     => "Yelmo Cines Ocimax Gijón",
    "id"       => "E0628",
    "url"      => "https://yelmocines.es/cartelera/asturias/ocimax-gijon",
    "check_vo" => true,
    "yelmo_id" => "asturias/ocimax-gijon"
  }.freeze

  def test_a_screening_sensacine_calls_dubbed_and_yelmo_calls_subtitled_is_listed
    potter = film("Harry Potter y la Piedra Filosofal", year: 2001)
    outbox = Outbox.new

    WeeklyNotifier.new(
      showtimes:       Listings.new("E0628" => [screening(potter, on: "2026-09-04", at: "17:00", original_version: false)]),
      yelmo_showtimes: Listings.new("asturias/ocimax-gijon" => [screening(potter, on: "2026-09-04", at: "17:00", original_version: true)]),
      movies_db:       MovieDatabase.new,
      messenger:       outbox,
      cinemas:         [OCIMAX]
    ).run(today: MONDAY)

    assert_equal ["17:00"], outbox.digest.times_listed_for("Harry Potter y la Piedra Filosofal")
  end

  def test_a_screening_both_providers_report_is_listed_once
    potter = film("Harry Potter y la Piedra Filosofal", year: 2001)
    outbox = Outbox.new

    WeeklyNotifier.new(
      showtimes:       Listings.new("E0628" => [screening(potter, on: "2026-09-04", at: "17:00")]),
      yelmo_showtimes: Listings.new("asturias/ocimax-gijon" => [screening(potter, on: "2026-09-04", at: "17:00")]),
      movies_db:       MovieDatabase.new,
      messenger:       outbox,
      cinemas:         [OCIMAX]
    ).run(today: MONDAY)

    assert_equal ["17:00"], outbox.digest.times_listed_for("Harry Potter y la Piedra Filosofal")
  end

  def test_the_dubbed_evening_screening_of_the_same_film_is_still_dropped
    # At Ocimax, Harry Potter runs subtitled at 17:00 and dubbed at 20:30 on
    # the same day. Only the first belongs in the digest.
    potter = film("Harry Potter y la Piedra Filosofal", year: 2001)
    outbox = Outbox.new

    WeeklyNotifier.new(
      showtimes: Listings.new("E0628" => [
        screening(potter, on: "2026-09-04", at: "17:00", original_version: false),
        screening(potter, on: "2026-09-04", at: "20:30", original_version: false)
      ]),
      yelmo_showtimes: Listings.new("asturias/ocimax-gijon" => [
        screening(potter, on: "2026-09-04", at: "17:00", original_version: true),
        screening(potter, on: "2026-09-04", at: "20:30", original_version: false)
      ]),
      movies_db: MovieDatabase.new,
      messenger: outbox,
      cinemas:   [OCIMAX]
    ).run(today: MONDAY)

    assert_equal ["17:00"], outbox.digest.times_listed_for("Harry Potter y la Piedra Filosofal")
  end

  def test_providers_are_matched_up_by_day_time_and_title
    # Yelmo bills the same screening as "…25 Aniversario", so the two records
    # are not recognised as one. That is survivable: the dubbed SensaCine entry
    # is filtered out on its own merits and Yelmo's subtitled one is kept, so
    # the screening still reaches the digest exactly once — under Yelmo's name.
    outbox = Outbox.new

    WeeklyNotifier.new(
      showtimes: Listings.new("E0628" => [
        screening(film("Harry Potter y la Piedra Filosofal", year: 2001),
                  on: "2026-09-04", at: "17:00", original_version: false)
      ]),
      yelmo_showtimes: Listings.new("asturias/ocimax-gijon" => [
        screening(film("Harry Potter y la Piedra Filosofal 25 Aniversario"),
                  on: "2026-09-04", at: "17:00", original_version: true)
      ]),
      movies_db: MovieDatabase.new,
      messenger: outbox,
      cinemas:   [OCIMAX]
    ).run(today: MONDAY)

    assert outbox.digest.mentions?("Harry Potter y la Piedra Filosofal 25 Aniversario")
    assert_equal ["17:00"], outbox.digest.times_listed_for("Harry Potter y la Piedra Filosofal 25 Aniversario")
  end

  def test_yelmo_is_not_consulted_about_a_cinema_it_does_not_run
    los_fresnos = { "name" => "Ocine Premium Los Fresnos", "id" => "E2907", "check_vo" => true }
    dog_stars   = film("La constelación del perro", year: 2026)
    yelmo       = Listings.new({})

    WeeklyNotifier.new(
      showtimes:       Listings.new("E2907" => [screening(dog_stars, on: "2026-09-04", at: "21:15")]),
      yelmo_showtimes: yelmo,
      movies_db:       MovieDatabase.new,
      messenger:       Outbox.new,
      cinemas:         [los_fresnos]
    ).run(today: MONDAY)

    assert_empty yelmo.days_asked_about
  end

  def test_the_notifier_runs_without_a_yelmo_source_at_all
    # yelmo_showtimes is optional, so a deployment that only wants SensaCine
    # keeps working.
    potter = film("Harry Potter y la Piedra Filosofal", year: 2001)
    outbox = Outbox.new

    WeeklyNotifier.new(
      showtimes: Listings.new("E0628" => [screening(potter, on: "2026-09-04", at: "17:00")]),
      movies_db: MovieDatabase.new,
      messenger: outbox,
      cinemas:   [OCIMAX]
    ).run(today: MONDAY)

    assert_equal ["17:00"], outbox.digest.times_listed_for("Harry Potter y la Piedra Filosofal")
  end
end
