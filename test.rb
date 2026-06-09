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
require_relative "lib/film"
require_relative "lib/cinema"
require_relative "lib/screening_session"
require_relative "lib/rating"
require_relative "lib/sensacine_client"
require_relative "lib/tmdb_client"
require_relative "lib/weekly_digest"
require_relative "lib/plain_text_formatter"
require_relative "lib/html_formatter"
require_relative "lib/weekly_notifier"
require_relative "lib/stdout_messenger"

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

  def test_translated_when_original_title_differs
    film = Film.new(localized_title: "La sustancia", year: 2024, title: "The Substance")
    assert film.translated?
  end

  def test_not_translated_when_titles_match_or_title_unknown
    same    = Film.new(localized_title: "Nosferatu", year: 2024, title: "NOSFERATU")
    unknown = Film.new(localized_title: "Nosferatu", year: 2024)
    refute same.translated?
    refute unknown.translated?
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
# SensacineClient
# ---------------------------------------------------------------------------

class SensacineClientTest < Minitest::Test
  FakeResponse = Struct.new(:code, :body)

  def setup
    @client = SensacineClient.new
  end

  def fake_response(results)
    FakeResponse.new("200", JSON.generate("results" => results))
  end

  def entry(title:, year:, showtimes:)
    { "movie" => { "title" => title, "release" => { "year" => year } }, "showtimes" => showtimes }
  end

  def test_parses_original_version_session
    resp = fake_response([entry(
      title: "La sustancia", year: 2024,
      showtimes: { "original" => [{ "startsAt" => "2024-11-15T19:30:00" }] }
    )])

    @client.stub(:http_get, resp) do
      sessions = @client.fetch_theater_movie_sessions(date: "2024-11-15", theater_id: "E0628")
      assert_equal 1, sessions.length
      assert sessions.first.original_version?
      assert_match /sustancia/i, sessions.first.film.localized_title
      assert_match /19:30|19.30|1930|7.30|730/, sessions.first.starts_at.to_s
    end
  end

  def test_dubbed_session_is_not_original_version
    resp = fake_response([entry(
      title: "La sustancia", year: 2024,
      showtimes: { "dubbed" => [{ "startsAt" => "2024-11-15T17:00:00" }] }
    )])

    @client.stub(:http_get, resp) do
      sessions = @client.fetch_theater_movie_sessions(date: "2024-11-15", theater_id: "E0628")
      assert_equal 1, sessions.length
      refute sessions.first.original_version?
    end
  end

  def test_preserves_version_flag_for_multiple_buckets
    resp = fake_response([entry(
      title: "La sustancia", year: 2024,
      showtimes: {
        "original" => [{ "startsAt" => "2024-11-15T19:30:00" }],
        "dubbed"   => [{ "startsAt" => "2024-11-15T17:00:00" }]
      }
    )])

    @client.stub(:http_get, resp) do
      sessions = @client.fetch_theater_movie_sessions(date: "2024-11-15", theater_id: "E0628")
      assert_equal 2, sessions.length
      assert     sessions.find { |s| s.starts_at.to_s.match?(/19:30|19.30|1930/) }.original_version?
      refute     sessions.find { |s| s.starts_at.to_s.match?(/17:00|17.00|1700/) }.original_version?
    end
  end

  def test_returns_empty_for_error_response
    resp = FakeResponse.new("503", "")
    @client.stub(:http_get, resp) do
      sessions = @client.fetch_theater_movie_sessions(date: "2024-11-15", theater_id: "E0628")
      assert_empty sessions
    end
  end

  def test_skips_incomplete_showtimes
    resp = fake_response([entry(
      title: "La sustancia", year: 2024,
      showtimes: { "original" => [{ "startsAt" => nil }] }
    )])

    @client.stub(:http_get, resp) do
      sessions = @client.fetch_theater_movie_sessions(date: "2024-11-15", theater_id: "E0628")
      assert_empty sessions
    end
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

  def test_retrieves_original_title_from_search
    resp = fake_response([result(original_title: "The Substance", vote_average: 7.2)])

    @client.stub(:http_get, resp) do
      assert_match /substance/i, @client.fetch_original_title(@film)
    end
  end

  def test_returns_nil_when_no_search_results
    resp = fake_response([])
    @client.stub(:http_get, resp) do
      refute @client.fetch_original_title(@film)
    end
  end

  def test_returns_rating_for_clear_match
    resp = fake_response([
      result(original_title: "The Substance", vote_average: 7.2, vote_count: 1500),
      result(original_title: "Other Film",    vote_average: 3.1, vote_count: 200)
    ])

    @client.stub(:http_get, resp) do
      assert_match(/[[:graph:]]/, @client.rating_for(@film).to_s)
    end
  end

  def test_returns_null_for_ambiguous_match
    # 7.2 / 4.0 = 1.8 < AMBIGUITY_RATIO (2.0)
    resp = fake_response([
      result(original_title: "The Substance", vote_average: 7.2, vote_count: 1500),
      result(original_title: "Ambiguous",     vote_average: 4.0, vote_count: 800)
    ])

    @client.stub(:http_get, resp) do
      assert "#{@client.rating_for(@film)}"
    end
  end

  def test_returns_null_when_no_votes
    resp = fake_response([result(original_title: "The Substance", vote_average: 7.2, vote_count: 0)])

    @client.stub(:http_get, resp) do
      assert "#{@client.rating_for(@film)}"
    end
  end

  def test_returns_null_when_no_search_results
    resp = fake_response([])
    @client.stub(:http_get, resp) do
      assert "#{@client.rating_for(@film)}"
    end
  end
end

# ---------------------------------------------------------------------------
# Formatters
# ---------------------------------------------------------------------------

class FormatterTest < Minitest::Test
  def setup
    film = Film.new(localized_title: "La sustancia", year: 2024, title: "The Substance")
    cinema = Cinema.new(id: "1", name: "Test Cinema", url: "http://example.com", check_vo?: true)
    sessions = [
      ScreeningSession.new(film: film, date: "2024-11-15", starts_at: "19:30", original_version?: true),
      ScreeningSession.new(film: film, date: "2024-11-16", starts_at: "21:00", original_version?: true)
    ]
    listing = FilmListing.new(film: film, rating: Rating.new(score: 7.2), sessions: sessions)
    @digest = WeeklyDigest.new(
      from:          Date.new(2024, 11, 15),
      to:            Date.new(2024, 11, 21),
      programs:      [CinemaProgram.new(cinema: cinema, listings: [listing])],
      quiet_cinemas: ["Quiet Cinema"]
    )
  end

  def test_html_wraps_titles_in_markup
    output = HtmlFormatter.new.render(@digest)
    assert_match %r{<b>La sustancia</b>}, output
    assert_match %r{<i>\(The Substance\)</i>}, output
    assert_match %r{<a href="http://example.com">Test Cinema}, output
    assert_match %r{<pre>.*• Fri → 19:30.*</pre>}m, output
  end

  def test_plain_text_has_same_content_without_markup
    output = PlainTextFormatter.new.render(@digest)
    refute_match(/<[a-z]+>/, output)
    assert_match(/La sustancia \(The Substance\)/, output)
    assert_match(/• Fri → 19:30/, output)
    assert_match(/• Sat → 21:00/, output)
  end

  def test_lists_cinemas_without_vo_sessions
    [HtmlFormatter, PlainTextFormatter].each do |formatter|
      assert_match(/no VO sessions: Quiet Cinema/, formatter.new.render(@digest))
    end
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
    @cinemas = [Cinema.new(id: "1", name: "Test Cinema", url: "http://example.com", check_vo?: false)]
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

    notifier = WeeklyNotifier.new(showtimes: showtimes, movies_db: movies_db, formatter: HtmlFormatter.new, messenger: messenger, cinemas: @cinemas)
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

    notifier = WeeklyNotifier.new(showtimes: showtimes, movies_db: movies_db, formatter: HtmlFormatter.new, messenger: messenger, cinemas: @cinemas)
    notifier.run(today: Date.new(2024, 11, 15))

    # Times should be comma-separated without padding
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

    notifier = WeeklyNotifier.new(showtimes: showtimes, movies_db: movies_db, formatter: HtmlFormatter.new, messenger: messenger, cinemas: @cinemas)
    notifier.run(today: Date.new(2024, 11, 15))

    # Each day should be on its own line without padding alignment
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

    notifier = WeeklyNotifier.new(showtimes: showtimes, movies_db: movies_db, formatter: HtmlFormatter.new, messenger: messenger, cinemas: @cinemas)
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

    notifier = WeeklyNotifier.new(showtimes: showtimes, movies_db: movies_db, formatter: HtmlFormatter.new, messenger: messenger, cinemas: @cinemas)
    notifier.run(today: Date.new(2024, 11, 15))

    # All sessions should appear on each day, not truncated
    assert_match(/• Fri → 16:15, 18:15/, output, "Friday should show both sessions")
    assert_match(/• Sat → 16:15, 18:15/, output, "Saturday should show both sessions")
    assert_match(/• Sun → 16:15, 18:15/, output, "Sunday should show both sessions")
  end
end
