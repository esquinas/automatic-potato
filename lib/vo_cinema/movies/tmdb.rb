# frozen_string_literal: true

require "json"
require "uri"

module VoCinema
  module Movies
    # What TMDB knows about a film the cinemas listed in Spanish: its original
    # title, its rating, and whether it is a Spanish production.
    #
    # Three pure queries — nothing here mutates a Film. WeeklyNotifier owns that.
    class Tmdb
      DOMAIN          = "https://api.themoviedb.org"
      AMBIGUITY_RATIO = 2.0

      def initialize(api_key: ENV.fetch("TMDB_API_KEY"), http: Http::Client.new)
        @api_key = api_key
        @http    = http
      end

      def fetch_original_title(film)
        top_match_for(film.localized_title, film.year)&.dig("original_title")
      end

      def spanish_original?(film)
        top_match_for(film.localized_title, film.year)&.dig("original_language") == "es"
      end

      def rating_for(film)
        score = confident_score(search(film.title || film.localized_title, film.year))

        score ? Rating.new(score: score) : Rating.null
      end

      private

      def top_match_for(title, year) = search(title, year).first

      # TMDB always answers something, so a score is only worth printing when
      # the top result is clearly the film we meant: somebody has to have voted
      # on it, and it has to beat the runner-up clearly enough that the two are
      # not plausibly the same search gone wrong.
      def confident_score(results)
        top, runner_up = results
        return nil if top.nil? || top["vote_count"].to_i.zero?

        score       = top["vote_average"].to_f
        second_best = runner_up&.dig("vote_average").to_f
        return nil if second_best.positive? && score / second_best < AMBIGUITY_RATIO

        score
      end

      def search(title, year = nil)
        query = URI.encode_www_form(query: title, language: "es-ES", api_key: @api_key)
        query += "&year=#{year}" if year
        response = @http.get("#{DOMAIN}/3/search/movie?#{query}")
        # An empty list rather than nil: "TMDB had nothing for us" and "TMDB
        # would not answer" mean the same thing to every caller here, and a nil
        # would have each of them checking for it.
        return [] unless response.code == "200"

        JSON.parse(response.body)["results"] || []
      end
    end
  end
end
