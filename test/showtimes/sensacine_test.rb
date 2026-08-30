# frozen_string_literal: true

require "json"

# Showtimes::Sensacine turns one theatre-day of SensaCine's internal JSON into
# ScreeningSessions. It answers with every screening it finds, original version
# or not, and marks each one; deciding what to do with a dubbed screening is
# the notifier's job, not the client's.
class SensacineTest < ServiceTest
  include Screenings

  def setup
    @http   = FakeHttp.new
    @client = Showtimes::Sensacine.new(http: Http::Client.new(headers: Showtimes::Sensacine::HEADERS))
  end

  def sessions_on(date, theater_id: "E0628")
    @http.while_intercepting do
      @client.sessions_for(cinema("A cinema", sensacine_id: theater_id), date)
    end
  end

  def test_it_asks_for_one_theatre_on_one_day
    @http.answers "sensacine.com", body: Fixtures.read("sensacine/ocimax_all_dubbed.json")

    sessions_on("2026-08-28", theater_id: "E0628")

    assert_equal 1, @http.requests.length
    assert_equal "GET", @http.requests.first.verb
    assert_equal "https://www.sensacine.com/_/showtimes/theater-E0628/d-2026-08-28/",
                 @http.requests.first.url
  end

  def test_it_introduces_itself_as_a_browser_reading_the_cinema_listings
    # SensaCine's internal endpoint answers 403 to anything that does not look
    # like its own site being browsed, so these headers are load-bearing.
    @http.answers "sensacine.com", body: Fixtures.read("sensacine/ocimax_all_dubbed.json")

    sessions_on("2026-08-28", theater_id: "E0628")
    headers = @http.requests.first.headers

    assert_equal "application/json", headers["accept"]
    assert_equal "https://www.sensacine.com/cines/cine/", headers["referer"]
    assert_includes headers["user-agent"], "Mozilla/5.0"
    assert_includes headers["accept-language"], "es-ES"
  end

  def test_every_showtime_in_the_day_becomes_a_session
    # Two films at Yelmo Ocimax, two screenings each.
    @http.answers "sensacine.com", body: Fixtures.read("sensacine/ocimax_all_dubbed.json")

    sessions = sessions_on("2026-08-28", theater_id: "E0628")

    assert_equal 4, sessions.length
  end

  def test_a_session_knows_its_film_its_day_and_the_time_it_starts
    @http.answers "sensacine.com", body: Fixtures.read("sensacine/ocimax_all_dubbed.json")

    sessions = sessions_on("2026-08-28", theater_id: "E0628")
    dog_stars = sessions.select { |session| session.film.localized_title == "La constelación del perro" }

    assert_equal ["18:45", "21:15"], dog_stars.map(&:starts_at).sort
    assert_equal ["2026-08-28"], dog_stars.map(&:date).uniq
  end

  def test_a_dubbed_screening_is_not_an_original_version_screening
    @http.answers "sensacine.com", body: Fixtures.read("sensacine/ocimax_all_dubbed.json")

    sessions = sessions_on("2026-08-28", theater_id: "E0628")

    refute sessions.any?(&:original_version?),
           "Every screening in this day sits in the dubbed bucket"
  end

  def test_the_original_bucket_is_an_original_version_screening
    sessions = laboral_sessions

    harry_potter_at_17 = find_session(sessions, "Harry Potter y la Piedra Filosofal", "17:00")

    assert harry_potter_at_17.original_version?
  end

  def test_an_original_with_subtitles_is_an_original_version_screening
    # SensaCine splits subtitled prints into their own bucket: original_st.
    sessions = laboral_sessions

    harry_potter_at_20_30 = find_session(sessions, "Harry Potter y la Piedra Filosofal", "20:30")

    assert harry_potter_at_20_30.original_version?
  end

  def test_a_film_screened_in_its_own_language_is_an_original_version_screening
    # The "local" bucket: a Spanish production shown in Spanish. There is
    # nothing to dub, so its only print is the original one.
    sessions = laboral_sessions

    el_ser_querido = find_session(sessions, "El ser querido", "19:00")

    assert el_ser_querido.original_version?
  end

  def test_the_dubbed_print_of_a_film_that_also_screens_in_vo_is_still_dubbed
    sessions = laboral_sessions

    harry_potter_at_22_45 = find_session(sessions, "Harry Potter y la Piedra Filosofal", "22:45")

    refute harry_potter_at_22_45.original_version?
  end

  def test_a_screening_misfiled_as_dubbed_is_rescued_by_its_diffusion_version
    # Yelmo's subtitled screenings arrive in the dubbed bucket with
    # diffusionVersion "ORIGINAL". Trusting the bucket alone loses them.
    sessions = laboral_sessions

    dog_stars = find_session(sessions, "La constelación del perro", "21:15")

    assert dog_stars.original_version?
  end

  def test_a_day_whose_screenings_have_already_passed_yields_nothing
    # This is not "that day had no cinema". SensaCine only lists screenings you
    # could still buy a ticket for, so a day empties out as its programme
    # runs — by late evening every one of its screenings has gone, and the API
    # answers error: true with the message "next.showtime.on".
    #
    # This fixture is the real proof: it was captured at 01:26 Madrid time
    # asking about the previous day, when all of it was hours in the past.
    @http.answers "sensacine.com", body: Fixtures.read("sensacine/nothing_left_that_day.json")

    sessions = sessions_on("2026-08-27", theater_id: "E0628")

    assert_empty sessions
  end

  def test_such_a_day_says_when_the_next_screening_is
    # "next.showtime.on" plus a nextDate is the API confirming it is healthy
    # and simply out of showings — quite different from a 403 or a broken body.
    # Logging it is what tells the two apart when a week looks quiet.
    @http.answers "sensacine.com", body: Fixtures.read("sensacine/nothing_left_that_day.json")

    sessions_on("2026-08-27", theater_id: "E0628")

    assert_includes printed_output, "2026-08-28"
  end

  def test_a_provider_that_will_not_answer_costs_us_the_day_and_nothing_more
    @http.answers "sensacine.com", status: "503"

    sessions = sessions_on("2026-08-28", theater_id: "E0628")

    assert_empty sessions
  end

  def test_a_showtime_with_no_start_time_is_skipped_without_losing_the_others
    # Occasionally a screening is announced before its time is fixed.
    feed = Fixtures.parse("sensacine/ocimax_all_dubbed.json")
    feed["results"][0]["showtimes"]["dubbed"][0]["startsAt"] = nil
    @http.answers "sensacine.com", body: JSON.generate(feed)

    sessions = sessions_on("2026-08-28", theater_id: "E0628")

    assert_equal 3, sessions.length
  end

  def test_a_day_split_over_two_pages_is_read_to_the_end
    @http.answers "d-2026-08-28/?page=2", body: Fixtures.read("sensacine/ocimax_page_2_of_2.json")
    @http.answers "d-2026-08-28/",        body: Fixtures.read("sensacine/ocimax_page_1_of_2.json")

    sessions = sessions_on("2026-08-28", theater_id: "E0628")

    assert_equal ["La constelación del perro", "Tadeo Jones y la lámpara maravillosa"],
                 sessions.map { |session| session.film.localized_title }.uniq.sort
  end

  def test_a_page_that_comes_back_empty_ends_the_day_early
    empty_page_two = Fixtures.parse("sensacine/ocimax_page_2_of_2.json").merge("results" => [])
    @http.answers "d-2026-08-28/?page=2", body: JSON.generate(empty_page_two)
    @http.answers "d-2026-08-28/",        body: Fixtures.read("sensacine/ocimax_page_1_of_2.json")

    sessions = sessions_on("2026-08-28", theater_id: "E0628")

    assert_equal 1, sessions.length
    assert_equal 2, @http.requests.length
  end

  def test_a_film_carries_the_year_it_was_made
    # The year is what narrows the TMDB search: without it, "Harry Potter y la
    # Piedra Filosofal" is as good a match for the 25th-anniversary re-release
    # as for the film itself. SensaCine keeps it under movie.data.
    sessions = laboral_sessions

    potter = find_session(sessions, "Harry Potter y la Piedra Filosofal", "17:00")

    assert_equal 2001, potter.film.year
  end

  def test_a_film_with_no_production_year_falls_back_to_its_first_release
    # Some entries reach the feed with the movie.data block half filled in.
    # The release dates are the next best thing, and the earliest of them is
    # the one that dates the film rather than a re-release.
    feed = Fixtures.parse("sensacine/ocimax_all_dubbed.json")
    feed["results"][0]["movie"]["data"].delete("productionYear")
    @http.answers "sensacine.com", body: JSON.generate(feed)

    sessions = sessions_on("2026-08-28", theater_id: "E0628")
    dog_stars = find_session(sessions, "La constelación del perro", "18:45")

    assert_equal 2026, dog_stars.film.year
  end

  def test_a_film_the_feed_dates_nowhere_at_all_simply_has_no_year
    # A yearless film is still worth listing; TMDB is asked about it without
    # the year filter rather than not asked at all.
    feed = Fixtures.parse("sensacine/ocimax_all_dubbed.json")
    feed["results"][0]["movie"]["data"].delete("productionYear")
    feed["results"][0]["movie"]["releases"] = []
    @http.answers "sensacine.com", body: JSON.generate(feed)

    sessions = sessions_on("2026-08-28", theater_id: "E0628")
    dog_stars = find_session(sessions, "La constelación del perro", "18:45")

    assert_nil dog_stars.film.year
  end

  private

  def laboral_sessions
    @http.answers "sensacine.com", body: Fixtures.read("sensacine/laboral_original_version.json")
    sessions_on("2026-08-29", theater_id: "G02A3")
  end

  def find_session(sessions, title, starts_at)
    sessions.find { |s| s.film.localized_title == title && s.starts_at == starts_at } ||
      flunk("No screening of #{title} at #{starts_at} in " \
            "#{sessions.map { |s| [s.film.localized_title, s.starts_at] }.inspect}")
  end
end
