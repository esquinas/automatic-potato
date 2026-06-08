#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"
  gem "minitest", "~> 5"
end

require "minitest/autorun"
require "minitest/mock"
require "json"
require_relative "lib/constants"
require_relative "lib/film"
require_relative "lib/screening_session"
require_relative "lib/rating"
require_relative "lib/screening_collection"
require_relative "lib/sensacine_client"
require_relative "lib/tmdb_client"
require_relative "lib/weekly_notifier"
require_relative "lib/stdout_messenger"
require_relative "lib/html_message"
require_relative "lib/plain_message"
require_relative "lib/parsers/sensacine_session_parser"
require_relative "lib/mappers/tmdb_movie_mapper"
require_relative "lib/services/film_enricher"
require_relative "lib/services/film_session_grouper"
require_relative "lib/presenters/film_presentation"

# ---------------------------------------------------------------------------
# Film
# ---------------------------------------------------------------------------

class FilmTest < Minitest::Test
  def test_films_equal_by_title_and_year
    a = Film.new(localized_title: "La sustancia", year: 2024)
    b = Film.new(localized_title: "La sustancia", year: 2024)
    assert_equal a, b
  end

  def test_different_years_are_not_equal
    a = Film.new(localized_title: "La sustancia", year: 2024)
    b = Film.new(localized_title: "La sustancia", year: 2023)
    refute_equal a, b
  end

  def test_film_has_title
    film = Film.new(localized_title: "La sustancia", year: 2024)
    assert_respond_to film, :title
  end

  def test_can_set_original_title
    film = Film.new(localized_title: "La sustancia", year: 2024)
    film.title = "The Substance"
    assert_match /substance/i, film.title
  end

  def test_can_be_used_as_hash_key
    film = Film.new(localized_title: "La sustancia", year: 2024)
    h = { film => :found }
    assert_equal :found, h[Film.new(localized_title: "La sustancia", year: 2024)]
  end
end

# ---------------------------------------------------------------------------
# Rating
# ---------------------------------------------------------------------------

class RatingTest < Minitest::Test
  def test_to_s_contains_printable_chars
    assert_match(/[[:graph:]]/, Rating.new(score: 7.2).to_s)
  end

  def test_null_to_s_is_string_safe
    assert "#{Rating.null}"
  end
end

# ---------------------------------------------------------------------------
# ScreeningSession
# ---------------------------------------------------------------------------

class ScreeningSessionTest < Minitest::Test
  def setup
    @film = Film.new(localized_title: "La sustancia", year: 2024)
  end

  def test_recognizes_original_version
    session = ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true)
    assert session.original_version?
  end

  def test_identifies_dubbed_version
    session = ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "17:00", original_version?: false)
    refute session.original_version?
  end
end

# ---------------------------------------------------------------------------
# ScreeningCollection
# ---------------------------------------------------------------------------

class ScreeningCollectionTest < Minitest::Test
  def setup
    @film = Film.new(localized_title: "La sustancia", year: 2024)
  end

  def test_organizes_sessions_by_date
    sessions = [
      ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true),
      ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "21:00", original_version?: true),
      ScreeningSession.new(film: @film, date: "2024-11-16", starts_at: "18:00", original_version?: true)
    ]
    collection = ScreeningCollection.new(@film, Rating.null, sessions)

    assert_equal 2, collection.dates_map.length
    assert_equal ["19:30", "21:00"], collection.dates_map["2024-11-15"]
    assert_equal ["18:00"], collection.dates_map["2024-11-16"]
  end

  def test_computes_all_times
    sessions = [
      ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true),
      ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "21:00", original_version?: true),
      ScreeningSession.new(film: @film, date: "2024-11-16", starts_at: "18:00", original_version?: true)
    ]
    collection = ScreeningCollection.new(@film, Rating.null, sessions)

    assert_equal ["18:00", "19:30", "21:00"], collection.all_times
  end

  def test_identifies_full_week
    sessions = 7.times.map { |i| ScreeningSession.new(film: @film, date: (Date.new(2024, 11, 15) + i).to_s, starts_at: "19:30", original_version?: true) }
    collection = ScreeningCollection.new(@film, Rating.null, sessions)

    assert collection.full_week?
  end

  def test_identifies_partial_week
    sessions = [
      ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true),
      ScreeningSession.new(film: @film, date: "2024-11-16", starts_at: "18:00", original_version?: true)
    ]
    collection = ScreeningCollection.new(@film, Rating.null, sessions)

    refute collection.full_week?
  end
end

# ---------------------------------------------------------------------------
# SensacineSessionParser
# ---------------------------------------------------------------------------

class SensacineSessionParserTest < Minitest::Test
  def setup
    @parser = Parsers::SensacineSessionParser.new
  end

  def entry(title:, year:, showtimes:)
    { "movie" => { "title" => title, "release" => { "year" => year } }, "showtimes" => showtimes }
  end

  def test_parses_original_version_session
    results = [entry(
      title: "La sustancia", year: 2024,
      showtimes: { "original" => [{ "startsAt" => "2024-11-15T19:30:00" }] }
    )]

    sessions = @parser.parse(results, "2024-11-15")
    assert_equal 1, sessions.length
    assert sessions.first.original_version?
    assert_match /sustancia/i, sessions.first.film.localized_title
    assert_equal "19:30", sessions.first.starts_at
  end

  def test_dubbed_session_is_not_original_version
    results = [entry(
      title: "La sustancia", year: 2024,
      showtimes: { "dubbed" => [{ "startsAt" => "2024-11-15T17:00:00" }] }
    )]

    sessions = @parser.parse(results, "2024-11-15")
    assert_equal 1, sessions.length
    refute sessions.first.original_version?
  end

  def test_local_bucket_is_original_version
    results = [entry(
      title: "La sustancia", year: 2024,
      showtimes: { "local" => [{ "startsAt" => "2024-11-15T19:30:00" }] }
    )]

    sessions = @parser.parse(results, "2024-11-15")
    assert_equal 1, sessions.length
    assert sessions.first.original_version?
  end

  def test_skips_incomplete_showtimes
    results = [entry(
      title: "La sustancia", year: 2024,
      showtimes: { "original" => [{ "startsAt" => nil }] }
    )]

    sessions = @parser.parse(results, "2024-11-15")
    assert_empty sessions
  end
end

# ---------------------------------------------------------------------------
# SensacineClient
# ---------------------------------------------------------------------------

class SensacineClientTest < Minitest::Test
  FakeResponse = Struct.new(:code, :body)

  def setup
    @parser = Parsers::SensacineSessionParser.new
    @client = SensacineClient.new(parser: @parser)
  end

  def fake_response(results)
    FakeResponse.new("200", JSON.generate("results" => results))
  end

  def entry(title:, year:, showtimes:)
    { "movie" => { "title" => title, "release" => { "year" => year } }, "showtimes" => showtimes }
  end

  def test_returns_empty_for_error_response
    resp = FakeResponse.new("503", "")
    @client.stub(:http_get, resp) do
      sessions = @client.fetch_theater_movie_sessions(date: "2024-11-15", theater_id: "E0628")
      assert_empty sessions
    end
  end

  def test_delegates_parsing_to_parser
    resp = fake_response([entry(
      title: "La sustancia", year: 2024,
      showtimes: { "original" => [{ "startsAt" => "2024-11-15T19:30:00" }] }
    )])

    @client.stub(:http_get, resp) do
      sessions = @client.fetch_theater_movie_sessions(date: "2024-11-15", theater_id: "E0628")
      assert_equal 1, sessions.length
      assert sessions.first.original_version?
    end
  end
end

# ---------------------------------------------------------------------------
# TmdbMovieMapper
# ---------------------------------------------------------------------------

class TmdbMovieMapperTest < Minitest::Test
  def setup
    @mapper = Mappers::TmdbMovieMapper.new
  end

  def result(original_title:, vote_average:, vote_count: 500)
    { "original_title" => original_title, "vote_average" => vote_average, "vote_count" => vote_count }
  end

  def test_extracts_original_title_from_results
    results = [result(original_title: "The Substance", vote_average: 7.2)]
    title = @mapper.extract_title(results)
    assert_match /substance/i, title
  end

  def test_returns_nil_when_no_results
    title = @mapper.extract_title([])
    assert_nil title
  end

  def test_extracts_rating_for_clear_match
    results = [
      result(original_title: "The Substance", vote_average: 7.2, vote_count: 1500),
      result(original_title: "Other Film",    vote_average: 3.1, vote_count: 200)
    ]
    rating = @mapper.extract_rating(results)
    assert_match(/[[:graph:]]/, rating.to_s)
  end

  def test_returns_null_for_ambiguous_match
    # 7.2 / 4.0 = 1.8 < AMBIGUITY_RATIO (2.0)
    results = [
      result(original_title: "The Substance", vote_average: 7.2, vote_count: 1500),
      result(original_title: "Ambiguous",     vote_average: 4.0, vote_count: 800)
    ]
    rating = @mapper.extract_rating(results)
    assert_equal "", rating.to_s
  end

  def test_returns_null_when_no_votes
    results = [result(original_title: "The Substance", vote_average: 7.2, vote_count: 0)]
    rating = @mapper.extract_rating(results)
    assert_equal "", rating.to_s
  end

  def test_returns_null_when_no_results
    rating = @mapper.extract_rating([])
    assert_equal "", rating.to_s
  end
end

# ---------------------------------------------------------------------------
# TmdbClient
# ---------------------------------------------------------------------------

class TmdbClientTest < Minitest::Test
  FakeResponse = Struct.new(:code, :body)

  def setup
    @client = TmdbClient.new(api_key: "test_key")
    @film   = Film.new(localized_title: "La sustancia", year: 2024)
  end

  def fake_response(results)
    FakeResponse.new("200", JSON.generate("results" => results))
  end

  def result(original_title:, vote_average:, vote_count: 500)
    { "original_title" => original_title, "vote_average" => vote_average, "vote_count" => vote_count }
  end

  def test_delegates_title_extraction_to_mapper
    resp = fake_response([result(original_title: "The Substance", vote_average: 7.2)])

    @client.stub(:http_get, resp) do
      title = @client.fetch_original_title(@film)
      assert_match /substance/i, title
    end
  end

  def test_delegates_rating_extraction_to_mapper
    resp = fake_response([
      result(original_title: "The Substance", vote_average: 7.2, vote_count: 1500),
      result(original_title: "Other Film",    vote_average: 3.1, vote_count: 200)
    ])

    @client.stub(:http_get, resp) do
      rating = @client.rating_for(@film)
      assert_match(/[[:graph:]]/, rating.to_s)
    end
  end
end

# ---------------------------------------------------------------------------
# FilmEnricher
# ---------------------------------------------------------------------------

class FilmEnricherTest < Minitest::Test
  def setup
    @film1 = Film.new(localized_title: "La sustancia", year: 2024)
    @film2 = Film.new(localized_title: "Otro film", year: 2023)
  end

  def test_enriches_films_with_titles
    sessions = [
      ScreeningSession.new(film: @film1, date: "2024-11-15", starts_at: "19:30", original_version?: true),
      ScreeningSession.new(film: @film2, date: "2024-11-15", starts_at: "21:00", original_version?: true)
    ]

    movies_db = Minitest::Mock.new
    movies_db.expect(:fetch_original_title, "The Substance", [@film1])
    movies_db.expect(:fetch_original_title, "Another Film", [@film2])

    enricher = Services::FilmEnricher.new(movies_db)
    enriched = enricher.enrich(sessions)

    assert_equal "The Substance", sessions[0].film.title
    assert_equal "Another Film", sessions[1].film.title
    assert_equal sessions, enriched
  end
end

# ---------------------------------------------------------------------------
# FilmSessionGrouper
# ---------------------------------------------------------------------------

class FilmSessionGrouperTest < Minitest::Test
  def setup
    @film1 = Film.new(localized_title: "La sustancia", year: 2024)
    @film2 = Film.new(localized_title: "Otro film", year: 2023)
  end

  def test_groups_sessions_by_film
    sessions = [
      ScreeningSession.new(film: @film1, date: "2024-11-15", starts_at: "19:30", original_version?: true),
      ScreeningSession.new(film: @film2, date: "2024-11-15", starts_at: "21:00", original_version?: true),
      ScreeningSession.new(film: @film1, date: "2024-11-16", starts_at: "18:00", original_version?: true)
    ]

    movies_db = Minitest::Mock.new
    movies_db.expect(:rating_for, Rating.new(score: 7.2), [@film1])
    movies_db.expect(:rating_for, Rating.new(score: 6.5), [@film2])

    grouper = Services::FilmSessionGrouper.new(movies_db)
    collections = grouper.group(sessions)

    assert_equal 2, collections.length
    assert_equal 2, collections[0].sessions.length
    assert_equal 1, collections[1].sessions.length
  end
end

# ---------------------------------------------------------------------------
# FilmPresentation
# ---------------------------------------------------------------------------

class FilmPresentationTest < Minitest::Test
  def setup
    @film = Film.new(localized_title: "La sustancia", year: 2024)
    @film.title = "The Substance"
  end

  def test_creates_from_full_week_collection
    sessions = 7.times.map { |i| ScreeningSession.new(film: @film, date: (Date.new(2024, 11, 15) + i).to_s, starts_at: "19:30", original_version?: true) }
    collection = ScreeningCollection.new(@film, Rating.new(score: 7.2), sessions)

    presentation = Presenters::FilmPresentation.from_screening_collection(collection)

    assert presentation.full_week
    assert_equal "2024-11-15", presentation.date_time_structure[:range_start]
    assert_equal "2024-11-21", presentation.date_time_structure[:range_end]
    assert_equal ["19:30"], presentation.date_time_structure[:times]
  end

  def test_creates_from_partial_week_collection
    sessions = [
      ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true),
      ScreeningSession.new(film: @film, date: "2024-11-16", starts_at: "18:00", original_version?: true)
    ]
    collection = ScreeningCollection.new(@film, Rating.new(score: 7.2), sessions)

    presentation = Presenters::FilmPresentation.from_screening_collection(collection)

    refute presentation.full_week
    assert presentation.date_time_structure.key?(:dates)
    assert_equal 2, presentation.date_time_structure[:dates].length
  end
end

# ---------------------------------------------------------------------------
# WeeklyNotifier
# ---------------------------------------------------------------------------

class WeeklyNotifierTest < Minitest::Test
  def setup
    @film = Film.new(localized_title: "La sustancia", year: 2024)
    @film.title = "The Substance"
    @messenger = StdoutMessenger.new
    @cinemas = [{ "name" => "Test Cinema", "id" => "1", "url" => "http://example.com", "check_vo" => false }]
  end

  def stub_showtimes_for_dates(sessions_by_date)
    showtimes = Minitest::Mock.new
    7.times do |offset|
      date = (Date.new(2024, 11, 15) + offset).to_s
      sessions = sessions_by_date[date] || []
      showtimes.expect(:fetch_theater_movie_sessions, sessions, date: date, theater_id: "1")
    end
    showtimes
  end

  def test_session_formatting_with_alignment
    sessions_by_date = { "2024-11-15" => [ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true)] }
    showtimes = stub_showtimes_for_dates(sessions_by_date)

    movies_db = Minitest::Mock.new
    movies_db.expect(:fetch_original_title, "The Substance", [@film])
    movies_db.expect(:rating_for, Rating.null, [@film])

    output = ""
    messenger = Minitest::Mock.new
    messenger.expect(:send_message, nil) { |msg| output = msg }

    notifier = WeeklyNotifier.new(showtimes: showtimes, movies_db: movies_db, messenger: messenger, cinemas: @cinemas)
    notifier.run(today: Date.new(2024, 11, 15))

    # Session line should have right-aligned times
    assert_match(/• Fri → 19:30/, output)
  end

  def test_session_formatting_multiple_times
    sessions_by_date = {
      "2024-11-15" => [
        ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true),
        ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "21:00", original_version?: true)
      ]
    }
    showtimes = stub_showtimes_for_dates(sessions_by_date)

    movies_db = Minitest::Mock.new
    movies_db.expect(:fetch_original_title, "The Substance", [@film])
    movies_db.expect(:rating_for, Rating.null, [@film])

    output = ""
    messenger = Minitest::Mock.new
    messenger.expect(:send_message, nil) { |msg| output = msg }

    notifier = WeeklyNotifier.new(showtimes: showtimes, movies_db: movies_db, messenger: messenger, cinemas: @cinemas)
    notifier.run(today: Date.new(2024, 11, 15))

    # Times should be comma-separated
    assert_match(/• Fri → 19:30, 21:00/, output)
  end

  def test_session_formatting_multiple_days
    sessions_by_date = {
      "2024-11-15" => [ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true)],
      "2024-11-16" => [
        ScreeningSession.new(film: @film, date: "2024-11-16", starts_at: "18:30", original_version?: true),
        ScreeningSession.new(film: @film, date: "2024-11-16", starts_at: "20:15", original_version?: true)
      ]
    }
    showtimes = stub_showtimes_for_dates(sessions_by_date)

    movies_db = Minitest::Mock.new
    movies_db.expect(:fetch_original_title, "The Substance", [@film])
    movies_db.expect(:rating_for, Rating.null, [@film])

    output = ""
    messenger = Minitest::Mock.new
    messenger.expect(:send_message, nil) { |msg| output = msg }

    notifier = WeeklyNotifier.new(showtimes: showtimes, movies_db: movies_db, messenger: messenger, cinemas: @cinemas)
    notifier.run(today: Date.new(2024, 11, 15))

    # Each day should be on its own line
    assert_match(/• Fri → 19:30/, output)
    assert_match(/• Sat → 18:30, 20:15/, output)
  end

  def test_session_lines_wrapped_in_pre_tags
    sessions_by_date = { "2024-11-15" => [ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true)] }
    showtimes = stub_showtimes_for_dates(sessions_by_date)

    movies_db = Minitest::Mock.new
    movies_db.expect(:fetch_original_title, "The Substance", [@film])
    movies_db.expect(:rating_for, Rating.null, [@film])

    output = ""
    messenger = Minitest::Mock.new
    messenger.expect(:send_message, nil) { |msg| output = msg }

    notifier = WeeklyNotifier.new(showtimes: showtimes, movies_db: movies_db, messenger: messenger, cinemas: @cinemas)
    notifier.run(today: Date.new(2024, 11, 15))

    # Session lines should be wrapped in <pre> tags for monospace rendering
    assert_match(/<pre>.*• Fri → 19:30.*<\/pre>/m, output)
  end

  def test_all_sessions_appear_with_proper_alignment
    # Verify all sessions appear and are right-aligned when times vary
    sessions_by_date = {
      "2024-11-15" => [
        ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "16:15", original_version?: true),
        ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "18:15", original_version?: true)
      ],
      "2024-11-16" => [
        ScreeningSession.new(film: @film, date: "2024-11-16", starts_at: "16:15", original_version?: true),
        ScreeningSession.new(film: @film, date: "2024-11-16", starts_at: "18:15", original_version?: true)
      ],
      "2024-11-17" => [
        ScreeningSession.new(film: @film, date: "2024-11-17", starts_at: "16:15", original_version?: true),
        ScreeningSession.new(film: @film, date: "2024-11-17", starts_at: "18:15", original_version?: true)
      ]
    }
    showtimes = stub_showtimes_for_dates(sessions_by_date)

    movies_db = Minitest::Mock.new
    movies_db.expect(:fetch_original_title, "The Substance", [@film])
    movies_db.expect(:rating_for, Rating.new(score: 6.9), [@film])

    output = ""
    messenger = Minitest::Mock.new
    messenger.expect(:send_message, nil) { |msg| output = msg }

    notifier = WeeklyNotifier.new(showtimes: showtimes, movies_db: movies_db, messenger: messenger, cinemas: @cinemas)
    notifier.run(today: Date.new(2024, 11, 15))

    # All sessions should appear on each day, not truncated
    assert_match(/• Fri → 16:15, 18:15/, output, "Friday should show both sessions")
    assert_match(/• Sat → 16:15, 18:15/, output, "Saturday should show both sessions")
    assert_match(/• Sun → 16:15, 18:15/, output, "Sunday should show both sessions")
  end
end
