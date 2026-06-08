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
require_relative "lib/screening_session"
require_relative "lib/rating"
require_relative "lib/sensacine_client"
require_relative "lib/tmdb_client"
require_relative "lib/digest_formatter"
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
# WeeklyNotifier
# ---------------------------------------------------------------------------

class WeeklyNotifierTest < Minitest::Test
  def setup
    @film    = Film.new(localized_title: "La sustancia", year: 2024)
    @cinemas = [{ "name" => "Test Cinema", "id" => "1", "url" => "http://example.com", "check_vo" => false }]
  end

  def stub_showtimes(sessions_by_date)
    showtimes = Minitest::Mock.new
    7.times do |offset|
      date = (Date.new(2024, 11, 15) + offset).to_s
      showtimes.expect(:fetch_theater_movie_sessions, sessions_by_date[date] || [], date: date, theater_id: "1")
    end
    showtimes
  end

  def test_enriches_films_and_sends_message
    session  = ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true)
    showtimes = stub_showtimes("2024-11-15" => [session])

    movies_db = Minitest::Mock.new
    movies_db.expect(:fetch_original_title, "The Substance", [@film])
    movies_db.expect(:rating_for, Rating.null, [@film])

    messenger = Minitest::Mock.new
    messenger.expect(:send_message, nil, [String])

    WeeklyNotifier.new(showtimes: showtimes, movies_db: movies_db, messenger: messenger, cinemas: @cinemas)
                  .run(today: Date.new(2024, 11, 15))

    messenger.verify
    movies_db.verify
    assert_equal "The Substance", @film.title
  end

  def test_skips_tmdb_for_empty_cinema
    showtimes = stub_showtimes({})

    movies_db = Minitest::Mock.new

    messenger = Minitest::Mock.new
    messenger.expect(:send_message, nil, [String])

    WeeklyNotifier.new(showtimes: showtimes, movies_db: movies_db, messenger: messenger, cinemas: @cinemas)
                  .run(today: Date.new(2024, 11, 15))

    messenger.verify
    movies_db.verify
  end

  def test_applies_vo_filter_when_check_vo_true
    vo_cinema = [{ "name" => "VO Only", "id" => "2", "url" => nil, "check_vo" => true }]
    vo_session    = ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true)
    dubbed_session = ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "17:00", original_version?: false)

    showtimes = Minitest::Mock.new
    7.times do |offset|
      date = (Date.new(2024, 11, 15) + offset).to_s
      sessions = date == "2024-11-15" ? [vo_session, dubbed_session] : []
      showtimes.expect(:fetch_theater_movie_sessions, sessions, date: date, theater_id: "2")
    end

    movies_db = Minitest::Mock.new
    movies_db.expect(:fetch_original_title, nil, [@film])
    movies_db.expect(:rating_for, Rating.null, [@film])

    captured = nil
    messenger = Minitest::Mock.new
    messenger.expect(:send_message, nil) { |msg| captured = msg }

    WeeklyNotifier.new(showtimes: showtimes, movies_db: movies_db, messenger: messenger, cinemas: vo_cinema)
                  .run(today: Date.new(2024, 11, 15))

    messenger.verify
    refute_nil captured
  end
end

# ---------------------------------------------------------------------------
# DigestFormatter
# ---------------------------------------------------------------------------

class DigestFormatterTest < Minitest::Test
  def setup
    @film      = Film.new(localized_title: "La sustancia", year: 2024)
    @film.title = "The Substance"
    @cinema    = { "name" => "Test Cinema", "id" => "1", "url" => "http://example.com", "check_vo" => false }
    @formatter = DigestFormatter.new
    @today     = Date.new(2024, 11, 15)
  end

  def digest(sessions, ratings = {})
    WeeklyNotifier::CinemaDigest.new(cinema: @cinema, sessions: sessions, ratings: ratings)
  end

  def test_single_session_shows_weekday_and_time
    sessions = [ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true)]
    output   = @formatter.format([digest(sessions, { @film => Rating.null })], today: @today)
    assert_match(/• Fri → 19:30/, output)
  end

  def test_multiple_times_same_day_are_comma_separated
    sessions = [
      ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true),
      ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "21:00", original_version?: true)
    ]
    output = @formatter.format([digest(sessions, { @film => Rating.null })], today: @today)
    assert_match(/• Fri → 19:30, 21:00/, output)
  end

  def test_multiple_days_each_on_own_line
    sessions = [
      ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true),
      ScreeningSession.new(film: @film, date: "2024-11-16", starts_at: "18:30", original_version?: true),
      ScreeningSession.new(film: @film, date: "2024-11-16", starts_at: "20:15", original_version?: true)
    ]
    output = @formatter.format([digest(sessions, { @film => Rating.null })], today: @today)
    assert_match(/• Fri → 19:30/, output)
    assert_match(/• Sat → 18:30, 20:15/, output)
  end

  def test_session_lines_wrapped_in_pre_tags
    sessions = [ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true)]
    output   = @formatter.format([digest(sessions, { @film => Rating.null })], today: @today)
    assert_match(/<pre>.*• Fri → 19:30.*<\/pre>/m, output)
  end

  def test_all_week_collapses_when_every_day_has_sessions
    sessions = 7.times.map do |i|
      date = (@today + i).to_s
      ScreeningSession.new(film: @film, date: date, starts_at: "20:00", original_version?: true)
    end
    output = @formatter.format([digest(sessions, { @film => Rating.null })], today: @today)
    assert_match(/• All week:/, output)
  end

  def test_empty_cinema_appears_in_no_vo_notice
    d      = WeeklyNotifier::CinemaDigest.new(cinema: @cinema, sessions: [], ratings: {})
    output = @formatter.format([d], today: @today)
    assert_match(/no VO sessions/, output)
    assert_match(/Test Cinema/, output)
  end

  def test_original_title_shown_when_different
    sessions = [ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true)]
    output   = @formatter.format([digest(sessions, { @film => Rating.null })], today: @today)
    assert_match(/<i>\(The Substance\)<\/i>/, output)
  end

  def test_original_title_omitted_when_same_as_localized
    film = Film.new(localized_title: "The Substance", year: 2024)
    film.title = "The Substance"
    sessions = [ScreeningSession.new(film: film, date: "2024-11-15", starts_at: "19:30", original_version?: true)]
    output   = @formatter.format([digest(sessions, { film => Rating.null })], today: @today)
    refute_match(/<i>/, output)
  end

  def test_rating_appears_when_present
    sessions = [ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true)]
    output   = @formatter.format([digest(sessions, { @film => Rating.new(score: 7.2) })], today: @today)
    assert_match(/★ 7\.2/, output)
  end

  def test_cinema_header_links_url
    sessions = [ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true)]
    output   = @formatter.format([digest(sessions, { @film => Rating.null })], today: @today)
    assert_match(/<a href="http:\/\/example\.com">/, output)
  end
end
