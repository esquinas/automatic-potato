# frozen_string_literal: true

require "date"
require "uri"
require_relative "../lib/sensacine_client"
require_relative "../lib/yelmo_client"
require_relative "../lib/tmdb_client"
require_relative "../lib/telegram_messenger"
require_relative "../lib/weekly_notifier"

# The whole service, wired exactly as bin/run.rb wires it, run against the
# payloads the real providers sent back on 28 August 2026. Nothing is faked
# except the network itself.
#
# Read this file first: it is the clearest statement of what the service does.
#
# The week under test starts Friday 28 August 2026 and covers:
#
#   Yelmo Cines Ocimax Gijón   both providers, filtered, Yelmo has the last word
#   Laboral Cinemateca         SensaCine only, filtered
#   Teatro Jovellanos          no original-version programme this week
class EndToEndTest < ServiceTest
  FRIDAY = Date.new(2026, 8, 28)

  CINEMAS = [
    { "name" => "Yelmo Cines Ocimax Gijón", "id" => "E0628",
      "url" => "https://yelmocines.es/cartelera/asturias/ocimax-gijon",
      "check_vo" => true, "yelmo_id" => "asturias/ocimax-gijon" },
    { "name" => "Teatro de la Laboral (Laboral Cinemateca)", "id" => "G02A3",
      "url" => "https://www.laboralcinemateca.es/en/venta-de-entradas", "check_vo" => true },
    { "name" => "Teatro Jovellanos", "id" => "G02E8",
      "url" => "https://teatrojovellanos.janto.es/" }
  ].freeze

  def setup
    @http = FakeHttp.new

    # SensaCine, day by day. The specific days come first because a matcher is
    # a substring of the URL and the catch-alls would otherwise swallow them.
    @http.answers "theater-E0628/d-2026-08-28/", body: Fixtures.read("sensacine/ocimax_all_dubbed.json")
    @http.answers "theater-G02A3/d-2026-08-29/", body: Fixtures.read("sensacine/laboral_original_version.json")
    @http.answers "sensacine.com", body: Fixtures.read("sensacine/nothing_left_that_day.json")

    # Yelmo answers with the whole of Asturias in one go.
    @http.answers "yelmocines.es", body: Fixtures.read("yelmo/now_playing_asturias.json")

    # TMDB, one search per film title the cinemas used.
    tmdb_knows "La constelación del perro",             "tmdb/search_la_constelacion_del_perro.json"
    tmdb_knows "Tadeo Jones y la lámpara maravillosa",  "tmdb/search_tadeo_jones.json"
    tmdb_knows "Tadeo Jones y La Lámpara Maravillosa",  "tmdb/search_tadeo_jones.json"
    tmdb_knows "Harry Potter y la Piedra Filosofal",    "tmdb/search_harry_potter.json"
    tmdb_knows "El ser querido",                        "tmdb/search_el_ser_querido.json"
    tmdb_knows "Una noche al año",                      "tmdb/search_una_noche_al_ano.json"
    tmdb_knows "The Dog Stars",                         "tmdb/search_la_constelacion_del_perro.json"
    tmdb_knows "Harry Potter and the Philosopher's Stone", "tmdb/search_harry_potter.json"
    # Yelmo bills the anniversary re-release under a title TMDB has never heard of.
    @http.answers "api.themoviedb.org", body: Fixtures.read("tmdb/search_no_results.json")

    @http.answers "api.telegram.org", body: '{"ok":true,"result":{"message_id":4127}}'
  end

  def digest
    @digest ||= begin
      @http.while_intercepting do
        WeeklyNotifier.new(
          showtimes:       SensacineClient.new,
          yelmo_showtimes: YelmoClient.new,
          movies_db:       TmdbClient.new(api_key: "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d"),
          messenger:       TelegramMessenger.new(token: "7842115903:AAH2-fake", chat_id: "-1001234567890"),
          cinemas:         CINEMAS
        ).run(today: FRIDAY)
      end
      RenderedDigest.new(JSON.parse(delivery.body)["text"])
    end
  end

  def delivery
    @http.requests_to("api.telegram.org").first
  end

  def ocimax  = digest.under("Yelmo Cines Ocimax Gijón")
  def laboral = digest.under("Teatro de la Laboral")

  def test_one_digest_is_delivered_to_the_telegram_channel
    digest

    assert_equal 1, @http.requests_to("api.telegram.org").length
    assert_equal "-1001234567890", JSON.parse(delivery.body)["chat_id"]
  end

  def test_a_subtitled_screening_at_yelmo_reaches_the_digest
    # Yelmo lists Harry Potter with Language "INGLÉS SUBTITULADO EN ESPAÑOL
    # (VOSE)" at 17:00. SensaCine files that same screening under "dubbed",
    # which is why the venue used to come back empty every week.
    assert_includes ocimax.times_listed_for("Harry Potter y la Piedra Filosofal 25 Aniversario"), "17:00"
  end

  def test_the_dubbed_evening_screening_of_that_same_film_does_not
    # Ocimax runs Harry Potter subtitled at 17:00 and dubbed at 20:30 daily.
    refute_includes ocimax.times_listed_for("Harry Potter y la Piedra Filosofal 25 Aniversario"), "20:30"
  end

  def test_a_spanish_production_reaches_the_digest_though_no_provider_marked_it
    # Yelmo lists Tadeo Jones as "ESPAÑOL", which is not a VO tag, so the
    # filter would drop it. TMDB says its original_language is "es": a Spanish
    # film has no dubbed version to be confused with, so this print is the
    # original one.
    assert ocimax.mentions?("Tadeo Jones y la lámpara maravillosa")
  end

  def test_a_foreign_film_dubbed_into_spanish_does_not
    # Una noche al año is One Night Only with a Spanish soundtrack.
    refute digest.mentions?("Una noche al año")
  end

  def test_the_original_bucket_at_the_laboral_reaches_the_digest
    assert_includes laboral.times_listed_for("Harry Potter y la Piedra Filosofal"), "17:00"
  end

  def test_an_original_with_subtitles_at_the_laboral_reaches_it_too
    assert_includes laboral.times_listed_for("Harry Potter y la Piedra Filosofal"), "20:30"
  end

  def test_a_subtitled_print_misfiled_as_dubbed_is_rescued_by_its_diffusion_version
    # The Laboral's 21:15 screening of La constelación del perro sits in the
    # dubbed bucket carrying diffusionVersion "ORIGINAL".
    assert_includes laboral.times_listed_for("La constelación del perro"), "21:15"
  end

  def test_the_dubbed_print_at_the_same_venue_does_not
    refute_includes laboral.times_listed_for("Harry Potter y la Piedra Filosofal"), "22:45"
  end

  def test_films_are_named_in_spanish_with_their_original_title_alongside
    assert digest.mentions?("La constelación del perro")
    assert digest.mentions?("The Dog Stars")
  end

  def test_a_film_whose_two_titles_only_differ_in_capitals_is_not_named_twice
    # SensaCine writes "Tadeo Jones y la lámpara maravillosa", TMDB writes
    # "Tadeo Jones y La Lámpara Maravillosa". They are the same title.
    assert_equal 1, ocimax.block_about("Tadeo Jones").lines.first.scan(/Tadeo Jones/i).length
  end

  def test_a_well_known_film_is_shown_with_its_tmdb_score
    assert_includes laboral.block_about("La constelación del perro"), "7.1"
  end

  def test_a_venue_with_nothing_on_is_named_at_the_end
    assert digest.mentions?("Teatro Jovellanos")
    assert digest.mentions?("no VO sessions")
  end

  def test_each_venue_is_headed_with_the_week_it_covers_and_a_link_to_its_page
    heading = digest.block_about("Teatro de la Laboral")

    assert_includes heading, "2026-08-28"
    assert_includes heading, "2026-09-03"
    assert_includes digest.links, "https://www.laboralcinemateca.es/en/venta-de-entradas"
  end

  def test_the_week_costs_one_request_per_cinema_day_plus_one_for_yelmo
    digest

    assert_equal 21, @http.requests_to("sensacine.com").length, "three cinemas over seven days"
    assert_equal 1, @http.requests_to("yelmocines.es").length, "one city, cached for the week"
  end

  def test_the_whole_week_fits_in_one_telegram_message
    # Deliberately not an exact-match assertion on the text: that would break
    # on every intentional wording change, and the tests above already pin down
    # everything the message has to say. What is left worth guarding is that a
    # digest comes out at all and that Telegram will accept it — it rejects
    # anything over 4096 characters outright.
    #
    # VERBOSE=1 ruby test.rb prints the digest, for anyone who wants to see the
    # shape of the thing rather than read assertions about it.
    puts "\n#{digest.text}\n" if ENV["VERBOSE"]

    refute_empty digest.raw
    assert_operator digest.raw.length, :<, 4096
  end

  private

  def tmdb_knows(title, fixture)
    @http.answers "query=#{URI.encode_www_form_component(title)}&", body: Fixtures.read(fixture)
  end
end
