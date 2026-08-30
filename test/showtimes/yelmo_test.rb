# frozen_string_literal: true

require "json"

# Showtimes::Yelmo exists because SensaCine gets Yelmo wrong: it files the cinema's
# subtitled screenings in the dubbed bucket alongside the Spanish ones. Yelmo's
# own listings label each print's language, so for that venue they are the
# authority.
#
# Yelmo answers with a whole city at once, so the client asks once and indexes
# the reply by day.
class YelmoTest < ServiceTest
  OCIMAX_GIJON = "asturias/ocimax-gijon"

  include Screenings

  def setup
    @http   = FakeHttp.new
    @client = Showtimes::Yelmo.new(http: Http::Client.new(headers: Showtimes::Yelmo::HEADERS))
    @http.answers "yelmocines.es", body: Fixtures.read("yelmo/now_playing_asturias.json")
  end

  def sessions_on(date, theater_id: OCIMAX_GIJON)
    @http.while_intercepting { @client.sessions_for(cinema("Ocimax", yelmo_id: theater_id), date) }
  end

  def test_it_asks_yelmo_for_a_whole_city_at_once
    sessions_on("2026-08-29")
    request = @http.requests.first

    assert_equal "POST", request.verb
    assert_equal "https://www.yelmocines.es/now-playing.aspx/GetNowPlaying", request.url
    assert_equal({ "cityKey" => "asturias" }, JSON.parse(request.body))
  end

  def test_it_asks_the_way_yelmo_s_own_page_asks
    # GetNowPlaying is the endpoint behind yelmocines.es/cartelera, and it only
    # answers requests that look like that page's own XHR.
    sessions_on("2026-08-29")
    headers = @http.requests.first.headers

    assert_equal "XMLHttpRequest", headers["x-requested-with"]
    assert_equal "https://www.yelmocines.es/cartelera", headers["referer"]
    assert_includes headers["content-type"], "application/json"
  end

  def test_a_subtitled_print_is_an_original_version_screening
    # "INGLÉS SUBTITULADO EN ESPAÑOL (VOSE)" — the whole reason this client
    # exists. SensaCine reports this same screening as dubbed.
    harry_potter_at_17 = find_session(sessions_on("2026-08-29"), "Harry Potter", "17:00")

    assert harry_potter_at_17.original_version?
  end

  def test_the_spanish_print_of_the_same_film_on_the_same_day_is_not
    # Harry Potter runs twice on 29 August at Ocimax: subtitled at 17:00 and
    # dubbed at 20:30. Only one of them is worth telling anyone about.
    harry_potter_at_20_30 = find_session(sessions_on("2026-08-29"), "Harry Potter", "20:30")

    refute harry_potter_at_20_30.original_version?
  end

  def test_every_screening_that_day_comes_back_whatever_its_language
    # Filtering is the notifier's decision, so the client hands over all of
    # them: Harry Potter twice, Tadeo Jones six times, Una noche al año four.
    assert_equal 12, sessions_on("2026-08-29").length
  end

  def test_the_day_is_read_from_yelmo_s_epoch_timestamp
    # Yelmo dates its listings as "/Date(1787979600000)/" rather than a plain
    # day, and the notifier matches sessions to days by that string.
    assert_equal ["2026-08-29"], sessions_on("2026-08-29").map(&:date).uniq
    assert_equal ["2026-08-30"], sessions_on("2026-08-30").map(&:date).uniq
  end

  def test_a_day_the_listings_do_not_cover_yields_nothing
    # Yelmo publishes a few days ahead; the notifier always asks for seven.
    assert_empty sessions_on("2026-09-04")
  end

  def test_asking_about_seven_days_costs_one_request
    # The notifier walks a week a day at a time. Doing that against a provider
    # that answers with the whole city would be seven identical requests.
    @http.while_intercepting do
      ocimax = cinema("Ocimax", yelmo_id: OCIMAX_GIJON)
      %w[2026-08-29 2026-08-30 2026-08-31 2026-09-01 2026-09-02 2026-09-03 2026-09-04].each do |date|
        @client.sessions_for(ocimax, date)
      end
    end

    assert_equal 1, @http.requests.length
  end

  def test_a_cinema_that_is_not_in_the_city_yields_nothing
    assert_empty sessions_on("2026-08-29", theater_id: "asturias/los-prados")
  end

  def test_a_cinema_that_is_not_in_the_city_says_which_ones_were
    # A typo in cinemas.yml should be obvious from the run log rather than
    # looking like a quiet week.
    sessions_on("2026-08-29", theater_id: "asturias/los-prados")

    assert_includes printed_output, "ocimax-gijon"
  end

  def test_a_provider_that_will_not_answer_yields_nothing
    http   = FakeHttp.new
    client = Showtimes::Yelmo.new(http: Http::Client.new(headers: Showtimes::Yelmo::HEADERS))
    http.answers "yelmocines.es", status: "500"

    sessions = http.while_intercepting do
      client.sessions_for(cinema("Ocimax", yelmo_id: OCIMAX_GIJON), "2026-08-29")
    end

    assert_empty sessions
  end

  private

  def find_session(sessions, title_fragment, starts_at)
    sessions.find { |s| s.film.localized_title.include?(title_fragment) && s.starts_at == starts_at } ||
      flunk("No screening of #{title_fragment} at #{starts_at} in " \
            "#{sessions.map { |s| [s.film.localized_title, s.starts_at] }.inspect}")
  end
end
