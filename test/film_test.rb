# frozen_string_literal: true

require_relative "../lib/film"
require_relative "../lib/rating"

# A Film is the one deliberately mutable object in the domain. The cinema
# providers only know a film by its Spanish release title; its original title
# arrives later, from TMDB, once the week's sessions have already been
# collected and are holding on to the film.
class FilmTest < ServiceTest
  def test_the_same_film_listed_on_two_days_is_one_film
    monday_listing = Film.new(localized_title: "La sustancia", year: 2024)
    friday_listing = Film.new(localized_title: "La sustancia", year: 2024)

    assert_equal monday_listing, friday_listing
  end

  def test_a_remake_is_not_the_film_it_remakes
    original = Film.new(localized_title: "Nosferatu", year: 1922)
    remake   = Film.new(localized_title: "Nosferatu", year: 2024)

    refute_equal original, remake
  end

  def test_the_original_title_is_unknown_until_tmdb_has_been_asked
    film = Film.new(localized_title: "La sustancia", year: 2024)

    assert_nil film.title

    film.title = "The Substance"

    assert_equal "The Substance", film.title
  end

  def test_learning_the_original_title_does_not_change_which_film_this_is
    # The notifier fills in .title after the week's ScreeningSessions are
    # already pointing at the film. If identity depended on the original
    # title, enrichment would orphan every session that referenced it.
    before_tmdb = Film.new(localized_title: "La sustancia", year: 2024)
    after_tmdb  = Film.new(localized_title: "La sustancia", year: 2024, title: "The Substance")

    assert_equal before_tmdb, after_tmdb
  end

  def test_a_film_can_key_a_hash_so_a_rating_looked_up_once_is_found_again
    ratings = { Film.new(localized_title: "La sustancia", year: 2024) => Rating.new(score: 7.1) }

    looked_up_again = ratings[Film.new(localized_title: "La sustancia", year: 2024)]

    assert_equal Rating.new(score: 7.1), looked_up_again
  end

  def test_a_film_is_not_equal_to_its_own_title
    film = Film.new(localized_title: "La sustancia", year: 2024)

    refute_equal film, "La sustancia"
  end
end
