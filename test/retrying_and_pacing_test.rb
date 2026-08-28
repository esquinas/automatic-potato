# frozen_string_literal: true

require "json"
require_relative "../lib/sensacine_client"

# How the service behaves towards a provider that is having a bad morning.
#
# Both cinema listings are scraped from endpoints meant for a browser, so the
# clients deliberately go slowly and give a failing request exactly one more
# chance. These tests drive that through a real client rather than through the
# module directly, so the promise holds however the retry is eventually
# organised in code.
class RetryingAndPacingTest < ServiceTest
  def setup
    @http   = FakeHttp.new
    @client = SensacineClient.new
  end

  def fetch_a_day
    @http.while_intercepting do
      @client.fetch_theater_movie_sessions(date: "2026-08-28", theater_id: "E0628")
    end
  end

  def test_a_provider_that_answers_first_time_is_asked_once
    @http.answers "sensacine.com", body: Fixtures.read("sensacine/ocimax_all_dubbed.json")

    fetch_a_day

    assert_equal 1, @http.requests.length
  end

  def test_a_request_that_fails_is_tried_once_more
    @http.answers_in_turn "sensacine.com", [
      { status: "503", body: "" },
      { status: "200", body: Fixtures.read("sensacine/ocimax_all_dubbed.json") }
    ]

    sessions = fetch_a_day

    assert_equal 2, @http.requests.length
    assert_equal 4, sessions.length, "the retry's answer is the one we keep"
  end

  def test_a_provider_that_stays_down_is_not_hammered
    # One retry, then the day is written off. The notifier carries on with the
    # other six days and the other seven cinemas.
    @http.answers "sensacine.com", status: "503"

    sessions = fetch_a_day

    assert_equal 2, @http.requests.length
    assert_empty sessions
  end

  def test_requests_are_spaced_out_rather_than_fired_back_to_back
    # Eight cinemas across seven days is fifty-six requests at an endpoint that
    # exists to serve a person clicking through a website.
    @http.answers "sensacine.com", body: Fixtures.read("sensacine/ocimax_all_dubbed.json")

    fetch_a_day

    assert RecordedSleeps.all.all?(&:positive?),
           "expected a pause after the request, got #{RecordedSleeps.all.inspect}"
  end

  def test_a_failure_makes_the_client_back_off_much_harder
    healthy_provider = FakeHttp.new
    healthy_provider.answers "sensacine.com", body: Fixtures.read("sensacine/ocimax_all_dubbed.json")
    healthy_provider.while_intercepting do
      SensacineClient.new.fetch_theater_movie_sessions(date: "2026-08-28", theater_id: "E0628")
    end
    pause_when_healthy = RecordedSleeps.all.max

    RecordedSleeps.reset

    flaky_provider = FakeHttp.new
    flaky_provider.answers_in_turn "sensacine.com", [
      { status: "503", body: "" },
      { status: "200", body: Fixtures.read("sensacine/ocimax_all_dubbed.json") }
    ]
    flaky_provider.while_intercepting do
      SensacineClient.new.fetch_theater_movie_sessions(date: "2026-08-28", theater_id: "E0628")
    end
    pause_after_failure = RecordedSleeps.all.max

    assert_operator pause_after_failure, :>, pause_when_healthy
  end
end
