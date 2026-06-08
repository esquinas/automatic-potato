# frozen_string_literal: true

require "json"
require "uri"
require_relative "http_client"
require_relative "mappers/tmdb_movie_mapper"

class TmdbClient
  include HttpClient

  DOMAIN = "https://api.themoviedb.org"

  def initialize(api_key: ENV.fetch("TMDB_API_KEY"), mapper: Mappers::TmdbMovieMapper.new)
    @api_key = api_key
    @mapper = mapper
  end

  def fetch_original_title(film)
    results = search(film.localized_title, film.year)
    @mapper.extract_title(results)
  end

  def rating_for(film)
    results = search(film.title || film.localized_title, film.year)
    @mapper.extract_rating(results)
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
