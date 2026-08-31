# frozen_string_literal: true

require "csv"
require "date"

# What the run log says about how much the providers agreed.
#
# The union rule hides a failing provider: if Yelmo stops tagging VOSE,
# SensaCine's records still carry the screenings, the merge still produces a
# digest, and the only symptom is a thinner one — which looks exactly like a
# quiet week at the cinema. Where two providers describe the same venue, the
# rate at which they contradict each other is a free drift detector.
#
# Read the numbers knowing that at Ocimax **disagreement is the healthy state**:
# SensaCine files Yelmo's subtitled prints as dubbed, so Yelmo is routinely the
# only one calling a screening original version.
class ProviderAgreementTest < ServiceTest
  include Screenings

  MONDAY = Date.new(2026, 8, 31)
  OCIMAX = "Yelmo Cines Ocimax Gijón"

  def ocimax
    cinema(OCIMAX, sensacine_id: "E0628", yelmo_id: "asturias/ocimax-gijon",
                   url: "https://yelmocines.es/cartelera/asturias/ocimax-gijon", check_vo: true)
  end

  def run_with(sensacine:, yelmo:, cinemas: [ocimax])
    outbox = Outbox.new
    WeeklyNotifier.new(
      showtimes: [Listings.named("SensaCine", cinemas.first.name => sensacine),
                  Listings.named("Yelmo", cinemas.first.name => yelmo)],
      movies_db: MovieDatabase.new, messenger: outbox, cinemas: cinemas
    ).run(today: MONDAY)
    outbox
  end

  # The block is CSV between markers on purpose: reading it by eye is enough
  # today, and appending it to a file later is a change to the workflow rather
  # than to the code.
  def reported
    block = printed_output[/===== BEGIN agreement =====\n(.*?)===== END agreement =====/m, 1]

    block ? CSV.parse(block, headers: true) : []
  end

  def test_a_screening_the_providers_describe_differently_is_counted_as_a_disagreement
    potter = film("Harry Potter y la Piedra Filosofal", year: 2001)

    run_with(
      sensacine: [screening(potter, on: "2026-09-04", at: "17:00", original_version: false)],
      yelmo:     [screening(potter, on: "2026-09-04", at: "17:00", original_version: true)]
    )

    assert_equal "1", reported.first["overlapping"]
    assert_equal "1", reported.first["disagreed"]
  end

  def test_the_provider_that_was_the_only_one_calling_it_original_version_is_named
    # The drift signal itself. If Yelmo stops tagging VOSE this column empties
    # while overlapping stays high, which is the thing worth noticing.
    potter = film("Harry Potter y la Piedra Filosofal", year: 2001)

    run_with(
      sensacine: [screening(potter, on: "2026-09-04", at: "17:00", original_version: false)],
      yelmo:     [screening(potter, on: "2026-09-04", at: "17:00", original_version: true)]
    )

    assert_equal "Yelmo", reported.first["sole_vo_source"]
  end

  def test_providers_that_agree_report_no_disagreement_over_a_real_denominator
    # At Ocimax this is the shape that means "go and look": SensaCine is known
    # to misfile Yelmo's subtitled prints, so the two of them agreeing about
    # every screening in a week is evidence that one has changed shape.
    potter = film("Harry Potter y la Piedra Filosofal", year: 2001)

    run_with(
      sensacine: [screening(potter, on: "2026-09-04", at: "17:00", original_version: true)],
      yelmo:     [screening(potter, on: "2026-09-04", at: "17:00", original_version: true)]
    )

    assert_equal "1", reported.first["overlapping"]
    assert_equal "0", reported.first["disagreed"]
  end

  def test_a_venue_only_one_provider_covers_is_left_out_of_the_report
    # It has no health signal to give — nothing can disagree with a single
    # voice — and a row of zeroes would read as a finding rather than silence.
    laboral = cinema("Teatro de la Laboral (Laboral Cinemateca)", sensacine_id: "G02A3", check_vo: true)
    querido = film("El ser querido", year: 2026)

    run_with(
      sensacine: [screening(querido, on: "2026-09-04", at: "19:00", original_version: true)],
      yelmo:     [],
      cinemas:   [laboral]
    )

    assert_empty reported
  end

  def test_a_film_the_director_rescued_is_counted_as_rescued
    # What makes the matching rules safe to loosen: a change that makes this
    # number jump is visible instead of silent.
    run_with(
      sensacine: [screening(film("Harry Potter y la Piedra Filosofal", year: 2001, director: "Chris Columbus"),
                            on: "2026-09-04", at: "17:00", original_version: true)],
      yelmo:     [screening(film("Harry Potter y la Piedra Filosofal 25 Aniversario", director: "Chris Columbus"),
                            on: "2026-09-04", at: "17:00", original_version: true)]
    )

    assert_equal "0", reported.first["by_title"]
    assert_equal "1", reported.first["by_director"]
  end

  def test_records_that_never_found_each_other_are_counted_as_unmatched
    # Two providers reporting at the same minute, neither record matching the
    # other: the population the director rescue is trying to reach.
    run_with(
      sensacine: [screening(film("Harry Potter y la Piedra Filosofal", year: 2001),
                            on: "2026-09-04", at: "17:00", original_version: true)],
      yelmo:     [screening(film("Una noche al año"), on: "2026-09-04", at: "17:00", original_version: true)]
    )

    assert_equal "0", reported.first["overlapping"], "two different films are not one screening"
    assert_equal "2", reported.first["unmatched"]
  end

  def test_the_numbers_reach_the_run_log_and_never_the_digest
    # Provider health is not something a subscriber should have to read about.
    potter = film("Harry Potter y la Piedra Filosofal", year: 2001)

    outbox = run_with(
      sensacine: [screening(potter, on: "2026-09-04", at: "17:00", original_version: false)],
      yelmo:     [screening(potter, on: "2026-09-04", at: "17:00", original_version: true)]
    )

    assert_includes printed_output, "BEGIN agreement"
    refute outbox.digest.mentions?("agreement")
    refute outbox.digest.mentions?("sole_vo_source")
    refute outbox.digest.mentions?("SensaCine")
  end

  def test_a_cinema_whose_name_contains_a_comma_does_not_break_the_columns
    # Cinema names come from config/cinemas.yml, which anyone can edit.
    awkward = cinema("Ocimax, Gijón", sensacine_id: "E0628", yelmo_id: "asturias/ocimax-gijon", check_vo: true)
    potter  = film("Harry Potter y la Piedra Filosofal", year: 2001)

    run_with(
      sensacine: [screening(potter, on: "2026-09-04", at: "17:00", original_version: false)],
      yelmo:     [screening(potter, on: "2026-09-04", at: "17:00", original_version: true)],
      cinemas:   [awkward]
    )

    assert_equal "Ocimax, Gijón", reported.first["cinema"]
    assert_equal "1", reported.first["disagreed"]
  end
end
