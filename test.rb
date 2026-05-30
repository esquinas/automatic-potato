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
require_relative "bin/run"

# ---------------------------------------------------------------------------
# Film
# ---------------------------------------------------------------------------

class FilmTest < Minitest::Test
  def test_equality_by_localized_title_and_year
    a = Film.new(localized_title: "La sustancia", year: 2024)
    b = Film.new(localized_title: "La sustancia", year: 2024)
    assert_equal a, b
  end

  def test_different_year_is_not_equal
    a = Film.new(localized_title: "La sustancia", year: 2024)
    b = Film.new(localized_title: "La sustancia", year: 2023)
    refute_equal a, b
  end

  def test_title_defaults_to_nil
    film = Film.new(localized_title: "La sustancia", year: 2024)
    assert_nil film.title
  end

  def test_title_is_mutable
    film = Film.new(localized_title: "La sustancia", year: 2024)
    film.title = "The Substance"
    assert_equal "The Substance", film.title
  end

  def test_usable_as_hash_key
    film = Film.new(localized_title: "La sustancia", year: 2024)
    h = { film => :found }
    assert_equal :found, h[Film.new(localized_title: "La sustancia", year: 2024)]
  end
end

# ---------------------------------------------------------------------------
# Rating
# ---------------------------------------------------------------------------

class RatingTest < Minitest::Test
  def test_present
    assert Rating.new(score: 7.2).present?
  end

  def test_formatted
    assert_equal "★ 7.2", Rating.new(score: 7.2).formatted
  end

  def test_null_not_present
    refute Rating.null.present?
  end

  def test_null_formatted_is_nil
    assert_nil Rating.null.formatted
  end

  def test_null_is_singleton
    assert_same Rating.null, Rating.null
  end
end

# ---------------------------------------------------------------------------
# ScreeningSession
# ---------------------------------------------------------------------------

class ScreeningSessionTest < Minitest::Test
  def setup
    @film = Film.new(localized_title: "La sustancia", year: 2024)
  end

  def test_original_version_true
    session = ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "19:30", original_version?: true)
    assert session.original_version?
  end

  def test_original_version_false_for_dubbed
    session = ScreeningSession.new(film: @film, date: "2024-11-15", starts_at: "17:00", original_version?: false)
    refute session.original_version?
  end
end

# ---------------------------------------------------------------------------
# SensacineAdapter
# ---------------------------------------------------------------------------

class SensacineAdapterTest < Minitest::Test
  FakeResponse = Struct.new(:code, :body)

  def setup
    @adapter = SensacineAdapter.new
  end

  def fake_response(results)
    FakeResponse.new("200", JSON.generate("results" => results))
  end

  def entry(title:, year:, showtimes:)
    { "movie" => { "title" => title, "release" => { "year" => year } }, "showtimes" => showtimes }
  end

  def test_parses_original_session
    resp = fake_response([entry(
      title: "La sustancia", year: 2024,
      showtimes: { "original" => [{ "startsAt" => "2024-11-15T19:30:00" }] }
    )])

    @adapter.stub(:http_get, resp) do
      sessions = @adapter.fetch_theater_movie_sessions(date: "2024-11-15", theater_id: "E0628")
      assert_equal 1, sessions.length
      assert sessions.first.original_version?
      assert_equal "La sustancia", sessions.first.film.localized_title
      assert_equal "19:30", sessions.first.starts_at
    end
  end

  def test_dubbed_session_is_not_original_version
    resp = fake_response([entry(
      title: "La sustancia", year: 2024,
      showtimes: { "dubbed" => [{ "startsAt" => "2024-11-15T17:00:00" }] }
    )])

    @adapter.stub(:http_get, resp) do
      sessions = @adapter.fetch_theater_movie_sessions(date: "2024-11-15", theater_id: "E0628")
      assert_equal 1, sessions.length
      refute sessions.first.original_version?
    end
  end

  def test_mixed_buckets_preserve_original_version_flag
    resp = fake_response([entry(
      title: "La sustancia", year: 2024,
      showtimes: {
        "original" => [{ "startsAt" => "2024-11-15T19:30:00" }],
        "dubbed"   => [{ "startsAt" => "2024-11-15T17:00:00" }]
      }
    )])

    @adapter.stub(:http_get, resp) do
      sessions = @adapter.fetch_theater_movie_sessions(date: "2024-11-15", theater_id: "E0628")
      assert_equal 2, sessions.length
      assert     sessions.find { |s| s.starts_at == "19:30" }.original_version?
      refute     sessions.find { |s| s.starts_at == "17:00" }.original_version?
    end
  end

  def test_returns_empty_on_non_200
    resp = FakeResponse.new("503", "")
    @adapter.stub(:http_get, resp) do
      sessions = @adapter.fetch_theater_movie_sessions(date: "2024-11-15", theater_id: "E0628")
      assert_empty sessions
    end
  end

  def test_skips_showtime_without_starts_at
    resp = fake_response([entry(
      title: "La sustancia", year: 2024,
      showtimes: { "original" => [{ "startsAt" => nil }] }
    )])

    @adapter.stub(:http_get, resp) do
      sessions = @adapter.fetch_theater_movie_sessions(date: "2024-11-15", theater_id: "E0628")
      assert_empty sessions
    end
  end
end

# ---------------------------------------------------------------------------
# TmdbAdapter
# ---------------------------------------------------------------------------

class TmdbAdapterTest < Minitest::Test
  FakeResponse = Struct.new(:code, :body)

  def setup
    @adapter = TmdbAdapter.new(api_key: "test_key")
    @film    = Film.new(localized_title: "La sustancia", year: 2024)
  end

  def fake_response(results)
    FakeResponse.new("200", JSON.generate("results" => results))
  end

  def result(original_title:, vote_average:, vote_count: 500)
    { "original_title" => original_title, "vote_average" => vote_average, "vote_count" => vote_count }
  end

  def test_fetch_original_title_returns_first_result
    resp = fake_response([result(original_title: "The Substance", vote_average: 7.2)])

    @adapter.stub(:http_get, resp) do
      assert_equal "The Substance", @adapter.fetch_original_title(@film)
    end
  end

  def test_fetch_original_title_returns_nil_on_empty
    resp = fake_response([])
    @adapter.stub(:http_get, resp) do
      assert_nil @adapter.fetch_original_title(@film)
    end
  end

  def test_rating_for_clear_winner
    resp = fake_response([
      result(original_title: "The Substance", vote_average: 7.2, vote_count: 1500),
      result(original_title: "Other Film",    vote_average: 3.1, vote_count: 200)
    ])

    @adapter.stub(:http_get, resp) do
      rating = @adapter.rating_for(@film)
      assert rating.present?
      assert_equal "★ 7.2", rating.formatted
    end
  end

  def test_rating_for_ambiguous_returns_null
    # 7.2 / 4.0 = 1.8 < TMDB_AMBIGUITY_RATIO (2.0)
    resp = fake_response([
      result(original_title: "The Substance", vote_average: 7.2, vote_count: 1500),
      result(original_title: "Ambiguous",     vote_average: 4.0, vote_count: 800)
    ])

    @adapter.stub(:http_get, resp) do
      refute @adapter.rating_for(@film).present?
    end
  end

  def test_rating_for_no_votes_returns_null
    resp = fake_response([result(original_title: "The Substance", vote_average: 7.2, vote_count: 0)])

    @adapter.stub(:http_get, resp) do
      refute @adapter.rating_for(@film).present?
    end
  end

  def test_rating_for_empty_results_returns_null
    resp = fake_response([])
    @adapter.stub(:http_get, resp) do
      refute @adapter.rating_for(@film).present?
    end
  end
end
