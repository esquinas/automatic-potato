# frozen_string_literal: true

require "json"
require "uri"

# Movies::Tmdb answers three questions about a film the cinemas only named in
# Spanish: what is it called originally, how is it rated, and was it made in
# Spanish in the first place.
#
# It is deliberately shy about ratings. A wrong star next to a film is worse
# than no star, so anything that looks like a doubtful match comes back as
# Rating.null and the digest simply says nothing.
class TmdbTest < ServiceTest
  def setup
    @http   = FakeHttp.new
    @client = Movies::Tmdb.new(api_key: "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d")
  end

  def answering_with(fixture)
    @http.answers "api.themoviedb.org", body: Fixtures.read(fixture)
  end

  def asking(&block)
    @http.while_intercepting(&block)
  end

  def test_the_same_question_twice_costs_one_request
    # #fetch_original_title and #spanish_original? ask TMDB exactly the same
    # thing, and the notifier asks about every screening rather than every
    # film, so a film showing all week used to send the same query fourteen
    # times over.
    answering_with("tmdb/search_el_ser_querido.json")
    querido = Film.new(localized_title: "El ser querido", year: 2026)

    asking do
      7.times do
        @client.fetch_original_title(querido)
        @client.spanish_original?(querido)
      end
    end

    assert_equal 1, @http.requests.length
  end

  def test_two_different_films_are_two_requests
    # The cache remembers an answer, it does not stop asking new questions.
    @http.answers "query=La+sustancia",    body: Fixtures.read("tmdb/search_la_sustancia.json")
    @http.answers "api.themoviedb.org",    body: Fixtures.read("tmdb/search_el_ser_querido.json")

    asking do
      @client.fetch_original_title(Film.new(localized_title: "La sustancia", year: 2024))
      @client.fetch_original_title(Film.new(localized_title: "El ser querido", year: 2026))
    end

    assert_equal 2, @http.requests.length
  end

  def test_the_same_title_in_two_different_years_is_two_questions
    # Nosferatu 1922 and Nosferatu 2024 are not the same film, and the year is
    # part of the query, so it has to be part of what is remembered.
    @http.answers "api.themoviedb.org", body: Fixtures.read("tmdb/search_no_results.json")

    asking do
      @client.fetch_original_title(Film.new(localized_title: "Nosferatu", year: 1922))
      @client.fetch_original_title(Film.new(localized_title: "Nosferatu", year: 2024))
    end

    assert_equal 2, @http.requests.length
  end

  def test_it_searches_by_the_spanish_release_title
    answering_with("tmdb/search_la_sustancia.json")
    film = Film.new(localized_title: "La sustancia", year: 2024)

    asking { @client.fetch_original_title(film) }
    query = URI.decode_www_form(URI(@http.requests.first.url).query).to_h

    assert_equal "La sustancia", query["query"]
    assert_equal "es-ES", query["language"]
    assert_equal "2024", query["year"]
  end

  def test_it_signs_the_search_with_the_api_key
    answering_with("tmdb/search_la_sustancia.json")

    asking { @client.fetch_original_title(Film.new(localized_title: "La sustancia", year: 2024)) }
    query = URI.decode_www_form(URI(@http.requests.first.url).query).to_h

    assert_equal "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d", query["api_key"]
  end

  def test_it_reads_its_key_from_the_environment_by_default
    # bin/run.rb builds every client with a bare .new; the credentials come
    # from the GitHub Actions secrets, or from .mise.toml when run locally.
    previous_key = ENV.fetch("TMDB_API_KEY", nil)
    ENV["TMDB_API_KEY"] = "key-from-the-environment"

    answering_with("tmdb/search_la_sustancia.json")
    asking { Movies::Tmdb.new.fetch_original_title(Film.new(localized_title: "La sustancia", year: 2024)) }
    query = URI.decode_www_form(URI(@http.requests.first.url).query).to_h

    assert_equal "key-from-the-environment", query["api_key"]
  ensure
    previous_key.nil? ? ENV.delete("TMDB_API_KEY") : ENV["TMDB_API_KEY"] = previous_key
  end

  def test_it_finds_the_original_title_behind_a_spanish_one
    answering_with("tmdb/search_la_sustancia.json")

    original_title = asking { @client.fetch_original_title(Film.new(localized_title: "La sustancia", year: 2024)) }

    assert_equal "The Substance", original_title
  end

  def test_a_film_tmdb_has_never_heard_of_has_no_original_title
    answering_with("tmdb/search_no_results.json")

    original_title = asking do
      @client.fetch_original_title(Film.new(localized_title: "Ciclo Buñuel: presentación", year: nil))
    end

    assert_nil original_title
  end

  def test_a_clear_match_is_rated
    answering_with("tmdb/search_harry_potter.json")

    rating = asking do
      @client.rating_for(Film.new(localized_title: "Harry Potter y la Piedra Filosofal", year: 2001))
    end

    assert_equal 7.903, rating.score
  end

  def test_two_plausible_matches_mean_no_rating_at_all
    # When the runner-up scores nearly as well as the winner, TMDB has probably
    # matched the wrong film. Saying nothing beats saying something wrong.
    ambiguous = Fixtures.parse("tmdb/search_el_ser_querido.json")
    ambiguous["results"] += Fixtures.parse("tmdb/search_una_noche_al_ano.json")["results"]
    @http.answers "api.themoviedb.org", body: JSON.generate(ambiguous)

    rating = asking { @client.rating_for(Film.new(localized_title: "El ser querido", year: 2026)) }

    assert_equal Rating.null, rating
  end

  def test_a_film_nobody_has_voted_on_is_not_rated
    # A brand-new release carries a vote_average of 0.0 with no votes behind
    # it; printing that as a score would libel the film.
    unvoted = Fixtures.parse("tmdb/search_una_noche_al_ano.json")
    unvoted["results"][0]["vote_count"]   = 0
    unvoted["results"][0]["vote_average"] = 0.0
    @http.answers "api.themoviedb.org", body: JSON.generate(unvoted)

    rating = asking { @client.rating_for(Film.new(localized_title: "Una noche al año", year: 2026)) }

    assert_equal Rating.null, rating
  end

  def test_a_film_tmdb_has_never_heard_of_is_not_rated
    answering_with("tmdb/search_no_results.json")

    rating = asking { @client.rating_for(Film.new(localized_title: "Ciclo Buñuel: presentación", year: nil)) }

    assert_equal Rating.null, rating
  end

  def test_once_the_original_title_is_known_the_rating_is_looked_up_by_it
    # The original title is the better search term, and by the time the rating
    # is wanted the notifier has already filled it in.
    answering_with("tmdb/search_la_sustancia.json")
    film = Film.new(localized_title: "La sustancia", year: 2024, title: "The Substance")

    asking { @client.rating_for(film) }
    query = URI.decode_www_form(URI(@http.requests.first.url).query).to_h

    assert_equal "The Substance", query["query"]
  end

  def test_a_spanish_production_is_recognised_as_such
    # No provider ever tags a Spanish film as VO — there is nothing to subtitle
    # — so this is the only way to tell it apart from a dubbed foreign film.
    answering_with("tmdb/search_el_ser_querido.json")

    spanish = asking { @client.spanish_original?(Film.new(localized_title: "El ser querido", year: 2026)) }

    assert spanish
  end

  def test_a_film_released_in_spanish_but_made_in_english_is_not_a_spanish_production
    answering_with("tmdb/search_la_sustancia.json")

    spanish = asking { @client.spanish_original?(Film.new(localized_title: "La sustancia", year: 2024)) }

    refute spanish
  end

  def test_a_film_tmdb_has_never_heard_of_is_not_assumed_to_be_spanish
    answering_with("tmdb/search_no_results.json")

    spanish = asking do
      @client.spanish_original?(Film.new(localized_title: "Ciclo Buñuel: presentación", year: nil))
    end

    refute spanish
  end

  def test_a_provider_that_will_not_answer_costs_a_rating_and_nothing_more
    @http.answers "api.themoviedb.org", status: "401"

    rating = asking { @client.rating_for(Film.new(localized_title: "La sustancia", year: 2024)) }

    assert_equal Rating.null, rating
  end

  def test_a_film_with_no_known_year_is_searched_without_one
    # Municipal venues list one-off screenings that carry no year at all.
    answering_with("tmdb/search_no_results.json")

    asking { @client.fetch_original_title(Film.new(localized_title: "Ciclo Buñuel: presentación", year: nil)) }

    refute_includes @http.requests.first.url, "year="
  end
end
