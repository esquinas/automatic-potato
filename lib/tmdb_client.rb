# frozen_string_literal: true

require "json"
require "uri"
require_relative "http_client"
require_relative "rating"

# What TMDB knows about a film the cinemas listed in Spanish: its original
# title, its rating, and whether it is a Spanish production.
#
# Three pure queries — nothing here mutates a Film. WeeklyNotifier owns that.
class TmdbClient
  include HttpClient

  DOMAIN          = "https://api.themoviedb.org"
  AMBIGUITY_RATIO = 2.0

  def initialize(api_key: ENV.fetch("TMDB_API_KEY"))
    @api_key = api_key
  end

  def fetch_original_title(film)
    search(film.localized_title, film.year)&.first&.dig("original_title")
  end

  def spanish_original?(film)
    search(film.localized_title, film.year)&.first&.dig("original_language") == "es"
  end

  def rating_for(film)
    results = search(film.title || film.localized_title, film.year)
    return Rating.null if results.nil? || results.empty?

    top    = results[0]
    second = results[1]

    return Rating.null if top["vote_count"].to_i.zero?

    top_score    = top["vote_average"].to_f
    second_score = (second&.dig("vote_average") || 0).to_f
    return Rating.null if second_score > 0 && top_score / second_score < AMBIGUITY_RATIO

    Rating.new(score: top_score)
  end

  private

  def search(title, year = nil)
    query = URI.encode_www_form(query: title, language: "es-ES", api_key: @api_key)
    query += "&year=#{year}" if year
    resp = http_get("#{DOMAIN}/3/search/movie?#{query}")
    return nil unless resp.code == "200"

    JSON.parse(resp.body)["results"] || []
  end
end
