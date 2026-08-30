# frozen_string_literal: true

require "date"

# Two providers describing the same cinema, and how their accounts are settled.
#
# The notifier is given an ordered list of showtimes providers and asks every
# one of them about every cinema. A provider that does not cover a venue says
# so by answering with nothing, and where two describe the same screening the
# later one in the list is believed — so the list runs from least to most
# authoritative.
#
# For Ocimax that ordering is the whole point: SensaCine files Yelmo's
# subtitled prints under "dubbed" alongside the Spanish ones, which used to
# empty the section for the venue most likely to have something worth seeing.
class WeeklyNotifierMergeTest < ServiceTest
  include Screenings

  MONDAY = Date.new(2026, 8, 31)
  OCIMAX = "Yelmo Cines Ocimax Gijón"

  def ocimax
    cinema(OCIMAX, sensacine_id: "E0628", yelmo_id: "asturias/ocimax-gijon",
                   url: "https://yelmocines.es/cartelera/asturias/ocimax-gijon", check_vo: true)
  end

  def digest_from(sensacine:, yelmo:, cinemas: [ocimax])
    outbox = Outbox.new
    WeeklyNotifier.new(
      showtimes: [Listings.new(OCIMAX => sensacine), Listings.new(OCIMAX => yelmo)],
      movies_db: MovieDatabase.new, messenger: outbox, cinemas: cinemas
    ).run(today: MONDAY)
    outbox
  end

  def test_a_screening_sensacine_calls_dubbed_and_yelmo_calls_subtitled_is_listed
    potter = film("Harry Potter y la Piedra Filosofal", year: 2001)

    outbox = digest_from(
      sensacine: [screening(potter, on: "2026-09-04", at: "17:00", original_version: false)],
      yelmo:     [screening(potter, on: "2026-09-04", at: "17:00", original_version: true)]
    )

    assert_equal ["17:00"], outbox.digest.times_listed_for("Harry Potter y la Piedra Filosofal")
  end

  def test_the_last_provider_is_believed_even_when_it_is_the_less_generous_one
    # The rule is positional, not "whoever says original version wins". Yelmo
    # is listed last because it is right about its own cinema — including when
    # being right means a screening SensaCine advertised as VO is not.
    potter = film("Harry Potter y la Piedra Filosofal", year: 2001)

    outbox = digest_from(
      sensacine: [screening(potter, on: "2026-09-04", at: "20:30", original_version: true)],
      yelmo:     [screening(potter, on: "2026-09-04", at: "20:30", original_version: false)]
    )

    assert outbox.digest.mentions?("Nothing left to catch")
    refute outbox.digest.mentions?("Harry Potter")
  end

  def test_a_screening_both_providers_report_is_listed_once
    potter = film("Harry Potter y la Piedra Filosofal", year: 2001)

    outbox = digest_from(
      sensacine: [screening(potter, on: "2026-09-04", at: "17:00")],
      yelmo:     [screening(potter, on: "2026-09-04", at: "17:00")]
    )

    assert_equal ["17:00"], outbox.digest.times_listed_for("Harry Potter y la Piedra Filosofal")
  end

  def test_the_dubbed_evening_screening_of_the_same_film_is_still_dropped
    # At Ocimax, Harry Potter runs subtitled at 17:00 and dubbed at 20:30 on
    # the same day. Only the first belongs in the digest.
    potter = film("Harry Potter y la Piedra Filosofal", year: 2001)

    outbox = digest_from(
      sensacine: [screening(potter, on: "2026-09-04", at: "17:00", original_version: false),
                  screening(potter, on: "2026-09-04", at: "20:30", original_version: false)],
      yelmo:     [screening(potter, on: "2026-09-04", at: "17:00", original_version: true),
                  screening(potter, on: "2026-09-04", at: "20:30", original_version: false)]
    )

    assert_equal ["17:00"], outbox.digest.times_listed_for("Harry Potter y la Piedra Filosofal")
  end

  def test_a_film_only_one_provider_can_date_is_still_one_film
    # Only SensaCine reports a year, and a Film is the same film only when the
    # year matches too. Left alone, Yelmo's yearless copy would reach the
    # digest as a second film of the same name, with the week's showtimes split
    # between the two entries.
    outbox = digest_from(
      sensacine: [screening(film("La constelación del perro", year: 2026), on: "2026-09-04", at: "18:45")],
      yelmo:     [screening(film("La constelación del perro"), on: "2026-09-05", at: "21:15")]
    )

    assert_equal 1, outbox.digest.text.scan("La constelación del perro").length
    assert_equal ["18:45", "21:15"], outbox.digest.times_listed_for("La constelación del perro").sort
  end

  def test_providers_are_matched_up_by_day_time_and_title
    # Yelmo bills the same screening as "…25 Aniversario", so the two records
    # are not recognised as one. That is survivable: the dubbed SensaCine entry
    # is filtered out on its own merits and Yelmo's subtitled one is kept, so
    # the screening still reaches the digest exactly once — under Yelmo's name.
    outbox = digest_from(
      sensacine: [screening(film("Harry Potter y la Piedra Filosofal", year: 2001),
                            on: "2026-09-04", at: "17:00", original_version: false)],
      yelmo:     [screening(film("Harry Potter y la Piedra Filosofal 25 Aniversario"),
                            on: "2026-09-04", at: "17:00", original_version: true)]
    )

    assert outbox.digest.mentions?("Harry Potter y la Piedra Filosofal 25 Aniversario")
    assert_equal ["17:00"], outbox.digest.times_listed_for("Harry Potter y la Piedra Filosofal 25 Aniversario")
  end

  def test_a_provider_is_still_asked_about_a_cinema_it_does_not_cover
    # It answers for itself. The notifier does not keep a table of which
    # provider runs which venue — that knowledge belongs to the provider, which
    # reads its own id out of the cinema and shrugs when there isn't one.
    los_fresnos = cinema("Ocine Premium Los Fresnos", sensacine_id: "E2907", check_vo: true)
    yelmo       = Listings.new({})

    WeeklyNotifier.new(
      showtimes: [Listings.new("Ocine Premium Los Fresnos" =>
                    [screening(film("La constelación del perro", year: 2026), on: "2026-09-04", at: "21:15")]),
                  yelmo],
      movies_db: MovieDatabase.new, messenger: Outbox.new, cinemas: [los_fresnos]
    ).run(today: MONDAY)

    assert_equal 7, yelmo.days_asked_about.length
    assert_equal ["Ocine Premium Los Fresnos"], yelmo.days_asked_about.map(&:first).uniq
  end

  def test_the_notifier_runs_with_a_single_provider
    potter = film("Harry Potter y la Piedra Filosofal", year: 2001)
    outbox = Outbox.new

    WeeklyNotifier.new(
      showtimes: [Listings.new(OCIMAX => [screening(potter, on: "2026-09-04", at: "17:00")])],
      movies_db: MovieDatabase.new, messenger: outbox, cinemas: [ocimax]
    ).run(today: MONDAY)

    assert_equal ["17:00"], outbox.digest.times_listed_for("Harry Potter y la Piedra Filosofal")
  end
end
