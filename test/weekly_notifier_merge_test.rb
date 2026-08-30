# frozen_string_literal: true

require "date"

# Two providers describing the same cinema, and how their accounts are settled.
#
# The notifier asks every provider about every cinema; one that does not cover
# a venue says so by answering with nothing. Where several describe the same
# screening they become one, and it is the original version if ANY of them
# said so.
#
# That rule is not a coin toss between equals. Calling a screening original
# version takes information; calling it dubbed is what a provider says when it
# has none. SensaCine files Yelmo's subtitled prints under "dubbed", and Yelmo
# labels a Spanish film "ESPAÑOL" when that print is the original — both are
# absences of evidence, and neither should be able to veto the other's
# positive.
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

  def test_when_providers_disagree_the_one_claiming_original_version_is_believed
    # Whichever of them says it, and whichever way round they are asked.
    potter = film("Harry Potter y la Piedra Filosofal", year: 2001)

    only_sensacine_says_so = digest_from(
      sensacine: [screening(potter, on: "2026-09-04", at: "20:30", original_version: true)],
      yelmo:     [screening(potter, on: "2026-09-04", at: "20:30", original_version: false)]
    )

    assert_equal ["20:30"], only_sensacine_says_so.digest.times_listed_for("Harry Potter y la Piedra Filosofal")
  end

  def test_a_screening_neither_provider_calls_original_version_is_dropped
    # The union is over positives; it does not invent one.
    potter = film("Harry Potter y la Piedra Filosofal", year: 2001)

    outbox = digest_from(
      sensacine: [screening(potter, on: "2026-09-04", at: "20:30", original_version: false)],
      yelmo:     [screening(potter, on: "2026-09-04", at: "20:30", original_version: false)]
    )

    assert outbox.digest.mentions?("Nothing left to catch")
    refute outbox.digest.mentions?("Harry Potter")
  end

  def test_the_order_the_providers_are_given_in_does_not_change_the_digest
    # A union has no favourites. Should a genuinely more authoritative provider
    # turn up, it will need conciliation logic of its own rather than a place
    # in this list — see the note in CLAUDE.md.
    potter    = film("Harry Potter y la Piedra Filosofal", year: 2001)
    dubbed    = [screening(potter, on: "2026-09-04", at: "20:30", original_version: false)]
    subtitled = [screening(potter, on: "2026-09-04", at: "20:30", original_version: true)]

    one_way   = digest_from(sensacine: dubbed,    yelmo: subtitled)
    other_way = digest_from(sensacine: subtitled, yelmo: dubbed)

    assert_equal one_way.digest.text, other_way.digest.text
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
