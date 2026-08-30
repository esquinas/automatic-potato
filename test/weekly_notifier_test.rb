# frozen_string_literal: true

require "date"
require_relative "../lib/weekly_notifier"

# WeeklyNotifier is the whole service in one object: it walks the coming week
# cinema by cinema, asks TMDB what each film is really called and how it is
# rated, lays the result out, and hands it to a messenger.
#
# It runs on a Monday, so the week in these tests is Monday 31 August 2026 to
# Sunday 6 September.
class WeeklyNotifierTest < ServiceTest
  include Screenings

  MONDAY = Date.new(2026, 8, 31)

  OCIMAX = {
    "name"     => "Yelmo Cines Ocimax Gijón",
    "id"       => "E0628",
    "url"      => "https://yelmocines.es/cartelera/asturias/ocimax-gijon",
    "check_vo" => true
  }.freeze

  LABORAL = {
    "name" => "Teatro de la Laboral (Laboral Cinemateca)",
    "id"   => "G02A3",
    "url"  => "https://www.laboralcinemateca.es/en/venta-de-entradas"
  }.freeze

  def test_it_asks_every_cinema_about_the_coming_seven_days
    listings = Listings.new("E0628" => [], "G02A3" => [])

    WeeklyNotifier.new(showtimes: listings, movies_db: MovieDatabase.new,
                       messenger: Outbox.new, cinemas: [OCIMAX, LABORAL]).run(today: MONDAY)

    assert_equal ["2026-08-31", "2026-09-01", "2026-09-02", "2026-09-03",
                  "2026-09-04", "2026-09-05", "2026-09-06"],
                 listings.days_asked_about.select { |theater, _| theater == "E0628" }.map(&:last)
    assert_equal 7, listings.days_asked_about.count { |theater, _| theater == "G02A3" }
  end

  def test_a_film_is_listed_once_with_all_of_its_showtimes
    substance = film("La sustancia", year: 2024)
    listings  = Listings.new("G02A3" => [
      screening(substance, on: "2026-09-04", at: "19:30"),
      screening(substance, on: "2026-09-05", at: "18:00"),
      screening(substance, on: "2026-09-05", at: "21:45")
    ])
    outbox = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: MovieDatabase.new,
                       messenger: outbox, cinemas: [LABORAL]).run(today: MONDAY)

    assert_equal ["18:00", "19:30", "21:45"], outbox.digest.times_listed_for("La sustancia").sort
    assert_equal 1, outbox.digest.text.scan("La sustancia").length
  end

  def test_showtimes_are_listed_in_order_and_a_repeated_time_is_listed_once
    # Two screens can run the same film at the same minute; the digest is a
    # list of when you could go, not of how many seats exist.
    substance = film("La sustancia", year: 2024)
    listings  = Listings.new("G02A3" => [
      screening(substance, on: "2026-09-04", at: "21:45"),
      screening(substance, on: "2026-09-04", at: "18:00"),
      screening(substance, on: "2026-09-04", at: "21:45")
    ])
    outbox = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: MovieDatabase.new,
                       messenger: outbox, cinemas: [LABORAL]).run(today: MONDAY)

    assert_equal ["18:00", "21:45"], outbox.digest.times_listed_for("La sustancia")
  end

  def test_each_day_of_the_week_is_named
    substance = film("La sustancia", year: 2024)
    listings  = Listings.new("G02A3" => [
      screening(substance, on: "2026-09-04", at: "19:30"),
      screening(substance, on: "2026-09-05", at: "18:00")
    ])
    outbox = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: MovieDatabase.new,
                       messenger: outbox, cinemas: [LABORAL]).run(today: MONDAY)
    block = outbox.digest.block_about("La sustancia")

    assert_includes block, "Fri"
    assert_includes block, "Sat"
  end

  def test_a_film_playing_every_single_day_is_summarised_rather_than_listed_seven_times
    # The long-running blockbuster would otherwise take seven lines and push
    # the interesting one-off screenings out of the message.
    tadeo    = film("Tadeo Jones y la lámpara maravillosa", year: 2026)
    all_week = (0..6).map { |offset| screening(tadeo, on: (MONDAY + offset).to_s, at: "18:10") }
    outbox   = Outbox.new

    WeeklyNotifier.new(showtimes: Listings.new("E0628" => all_week), movies_db: MovieDatabase.new,
                       messenger: outbox, cinemas: [OCIMAX]).run(today: MONDAY)
    block = outbox.digest.block_about("Tadeo Jones")

    assert_includes block, "All week"
    assert_includes block, "2026-08-31"
    assert_includes block, "2026-09-06"
    assert_equal 1, block.scan("18:10").length
  end

  def test_the_original_title_is_shown_next_to_the_spanish_one
    substance = film("La sustancia", year: 2024)
    listings  = Listings.new("G02A3" => [screening(substance, on: "2026-09-04", at: "19:30")])
    tmdb      = MovieDatabase.new(original_titles: { "La sustancia" => "The Substance" })
    outbox    = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: tmdb,
                       messenger: outbox, cinemas: [LABORAL]).run(today: MONDAY)

    assert outbox.digest.mentions?("La sustancia")
    assert outbox.digest.mentions?("The Substance")
  end

  def test_a_film_that_was_never_renamed_is_not_given_its_own_title_twice
    querido  = film("El ser querido", year: 2026)
    listings = Listings.new("G02A3" => [screening(querido, on: "2026-09-04", at: "19:00")])
    tmdb     = MovieDatabase.new(original_titles: { "El ser querido" => "El ser querido" })
    outbox   = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: tmdb,
                       messenger: outbox, cinemas: [LABORAL]).run(today: MONDAY)

    assert_equal 1, outbox.digest.text.scan("El ser querido").length
  end

  def test_a_rated_film_is_shown_with_its_score
    potter   = film("Harry Potter y la Piedra Filosofal", year: 2001)
    listings = Listings.new("G02A3" => [screening(potter, on: "2026-09-04", at: "17:00")])
    tmdb     = MovieDatabase.new(ratings: { "Harry Potter y la Piedra Filosofal" => Rating.new(score: 7.903) })
    outbox   = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: tmdb,
                       messenger: outbox, cinemas: [LABORAL]).run(today: MONDAY)

    assert_includes outbox.digest.block_about("Harry Potter"), "7.9"
  end

  def test_a_film_tmdb_would_not_commit_on_is_listed_with_no_score_and_no_gap
    # Rating.null renders as nothing at all, so the title line just ends.
    obscure  = film("Ciclo Buñuel: presentación")
    listings = Listings.new("G02A3" => [screening(obscure, on: "2026-09-04", at: "20:00")])
    outbox   = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: MovieDatabase.new,
                       messenger: outbox, cinemas: [LABORAL]).run(today: MONDAY)
    headline = outbox.digest.block_about("Ciclo Buñuel").lines.first.chomp

    assert_equal "Ciclo Buñuel: presentación", headline
  end

  def test_the_digest_says_that_today_only_covers_what_is_still_to_come
    # Neither provider lists a screening once it has started, so today's row is
    # always the rest of today. Saying so is what stops a reader concluding
    # that a film they can still catch tomorrow was not on at all.
    substance = film("La sustancia", year: 2024)
    listings  = Listings.new("G02A3" => [screening(substance, on: "2026-09-04", at: "19:30")])
    outbox    = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: MovieDatabase.new,
                       messenger: outbox, cinemas: [LABORAL]).run(today: MONDAY)

    assert outbox.digest.mentions?("still to come")
  end

  def test_a_venue_the_providers_had_nothing_left_for_is_not_said_to_have_had_nothing
    # "no sessions" would be a claim neither provider ever makes: an empty
    # answer means nothing is left to book, not that nothing was programmed.
    substance = film("La sustancia", year: 2024)
    listings  = Listings.new("G02A3" => [screening(substance, on: "2026-09-04", at: "19:30")],
                             "E0628" => [])
    outbox    = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: MovieDatabase.new,
                       messenger: outbox, cinemas: [OCIMAX, LABORAL]).run(today: MONDAY)

    assert outbox.digest.mentions?("Nothing left to catch this week at: Yelmo Cines Ocimax Gijón")
    refute_match(/\bno\b.{0,20}\bsessions\b/i, outbox.digest.text)
  end

  def test_a_venue_with_nothing_on_is_named_once_instead_of_given_a_section
    substance = film("La sustancia", year: 2024)
    listings  = Listings.new("G02A3" => [screening(substance, on: "2026-09-04", at: "19:30")],
                             "E0628" => [])
    outbox    = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: MovieDatabase.new,
                       messenger: outbox, cinemas: [OCIMAX, LABORAL]).run(today: MONDAY)

    assert outbox.digest.mentions?("Yelmo Cines Ocimax Gijón")
    assert outbox.digest.mentions?("Nothing left to catch")
    refute outbox.digest.mentions?("Yelmo Cines Ocimax Gijón — 2026-08-31")
  end

  def test_a_cinema_heading_links_to_the_venue_s_own_page
    substance = film("La sustancia", year: 2024)
    listings  = Listings.new("G02A3" => [screening(substance, on: "2026-09-04", at: "19:30")])
    outbox    = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: MovieDatabase.new,
                       messenger: outbox, cinemas: [LABORAL]).run(today: MONDAY)

    assert_includes outbox.digest.links, "https://www.laboralcinemateca.es/en/venta-de-entradas"
  end

  def test_a_cinema_with_no_page_of_its_own_still_gets_a_heading
    ateneo    = { "name" => "Centro Municipal Integrado Ateneo de La Calzada", "id" => "G02D6" }
    substance = film("La sustancia", year: 2024)
    listings  = Listings.new("G02D6" => [screening(substance, on: "2026-09-04", at: "19:30")])
    outbox    = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: MovieDatabase.new,
                       messenger: outbox, cinemas: [ateneo]).run(today: MONDAY)

    assert outbox.digest.mentions?("Centro Municipal Integrado Ateneo de La Calzada")
    assert_empty outbox.digest.links
  end

  def test_a_cinema_heading_covers_the_week_being_reported
    substance = film("La sustancia", year: 2024)
    listings  = Listings.new("G02A3" => [screening(substance, on: "2026-09-04", at: "19:30")])
    outbox    = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: MovieDatabase.new,
                       messenger: outbox, cinemas: [LABORAL]).run(today: MONDAY)
    heading = outbox.digest.block_about("Teatro de la Laboral")

    assert_includes heading, "2026-08-31"
    assert_includes heading, "2026-09-06"
  end

  def test_cinemas_appear_in_the_order_they_are_configured
    substance = film("La sustancia", year: 2024)
    potter    = film("Harry Potter y la Piedra Filosofal", year: 2001)
    listings  = Listings.new("E0628" => [screening(substance, on: "2026-09-04", at: "19:30")],
                             "G02A3" => [screening(potter, on: "2026-09-04", at: "17:00")])
    outbox    = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: MovieDatabase.new,
                       messenger: outbox, cinemas: [OCIMAX, LABORAL]).run(today: MONDAY)
    text = outbox.digest.text

    assert_operator text.index("Yelmo Cines Ocimax Gijón"), :<, text.index("Teatro de la Laboral")
  end

  def test_the_whole_week_arrives_as_a_single_message
    substance = film("La sustancia", year: 2024)
    listings  = Listings.new("E0628" => [screening(substance, on: "2026-09-04", at: "19:30")],
                             "G02A3" => [screening(substance, on: "2026-09-05", at: "17:00")])
    outbox    = Outbox.new

    WeeklyNotifier.new(showtimes: listings, movies_db: MovieDatabase.new,
                       messenger: outbox, cinemas: [OCIMAX, LABORAL]).run(today: MONDAY)

    assert_equal 1, outbox.messages.length
  end

  def test_an_unusually_busy_week_is_handed_over_whole
    # The notifier does not shorten anything. Telegram's 4096-character limit
    # is Telegram's, and TelegramMessenger enforces it; a messenger writing to
    # a terminal has no such limit and should get the lot.
    crowded_week = (1..60).flat_map do |n|
      title = film("Película número #{n} del ciclo de verano", year: 2026)
      [screening(title, on: "2026-09-04", at: "19:30"), screening(title, on: "2026-09-05", at: "21:00")]
    end
    outbox = Outbox.new

    WeeklyNotifier.new(showtimes: Listings.new("G02A3" => crowded_week), movies_db: MovieDatabase.new,
                       messenger: outbox, cinemas: [LABORAL]).run(today: MONDAY)

    assert_operator outbox.messages.first.length, :>, 4096
    refute outbox.digest.mentions?("truncated")
    assert outbox.digest.mentions?("Película número 1 del ciclo de verano")
    assert outbox.digest.mentions?("Película número 60 del ciclo de verano")
  end

  def test_a_week_with_nothing_anywhere_still_reports_back
    # Silence would be indistinguishable from a broken cron job.
    outbox = Outbox.new

    WeeklyNotifier.new(showtimes: Listings.new("E0628" => [], "G02A3" => []),
                       movies_db: MovieDatabase.new, messenger: outbox,
                       cinemas: [OCIMAX, LABORAL]).run(today: MONDAY)

    assert_equal 1, outbox.messages.length
    assert outbox.digest.mentions?("Yelmo Cines Ocimax Gijón")
    assert outbox.digest.mentions?("Teatro de la Laboral")
  end
end
