# frozen_string_literal: true

require "json"
require "uri"

module VoCinema
  module Movies
    class Tmdb
      # Every question this service puts to TMDB is the same question: search
      # for a title, narrowed to a year where one is known. This is the asking —
      # the URL, the request, and the answers already given. What the answers
      # mean is Tmdb's half.
      #
      # One request per question per run, however often it is asked.
      # #fetch_original_title and #spanish_original? ask TMDB exactly the same
      # thing, and the notifier asks about every screening of a film rather than
      # every film, so the same query went out two or three times over before
      # this. A client is built once per run, which makes it the right lifetime
      # for the answers.
      class Search
        def initialize(api_key:, http:)
          @api_key          = api_key
          @http             = http
          @answers_this_run = {}
        end

        # TMDB's matches for a title, best first.
        #
        # An empty list rather than nil: "TMDB had nothing for us" and "TMDB
        # would not answer" mean the same thing to every caller here, and a nil
        # would have each of them checking for it.
        def results_for(title, year)
          @answers_this_run[[title, year]] ||= fetch(title, year)
        end

        private

        def fetch(title, year)
          response = @http.get(search_url(title, year))
          return [] unless response.code == "200"

          JSON.parse(response.body)["results"] || []
        end

        def search_url(title, year)
          query = URI.encode_www_form(query: title, language: "es-ES", api_key: @api_key)
          query += "&year=#{year}" if year

          "#{DOMAIN}/3/search/movie?#{query}"
        end
      end
    end
  end
end
