# frozen_string_literal: true

require "json"
require "uri"

module VoCinema
  module Movies
    # What TMDB knows about a film the cinemas listed in Spanish: its original
    # title, its rating, whether it is a Spanish production, where its page on
    # TMDB is, and which country it comes from.
    #
    # Five pure queries — nothing here mutates a Film. WeeklyNotifier owns that.
    class Tmdb
      DOMAIN          = "https://api.themoviedb.org"
      SITE            = "https://www.themoviedb.org"
      AMBIGUITY_RATIO = 2.0

      def initialize(api_key: ENV.fetch("TMDB_API_KEY"), http: Http::Client.new)
        @api_key = api_key
        @http    = http
        @results = {}
        @details = {}
      end

      def fetch_original_title(film)
        top_match_for(film.localized_title, film.year)&.dig("original_title")
      end

      def spanish_original?(film)
        top_match_for(film.localized_title, film.year)&.dig("original_language") == "es"
      end

      # The same top match the original title comes from, so the link always
      # leads to the film whose title the digest prints beside it.
      def profile_url_for(film)
        id = top_match_for(film.localized_title, film.year)&.dig("id")

        id && "#{SITE}/movie/#{id}"
      end

      # The country the film is mainly from, as an ISO code ("US", "ES"). The
      # search results carry none, so this is the one question that costs a
      # second request: the film's own page, for the same top match the link
      # leads to. TMDB's origin_country is its answer to exactly this question;
      # production_countries is the fallback for an entry that leaves it empty.
      def origin_country_for(film)
        id = top_match_for(film.localized_title, film.year)&.dig("id")
        return nil unless id

        movie = details(id)
        Array(movie["origin_country"]).first || Array(movie["production_countries"]).first&.dig("iso_3166_1")
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

      # One request per question per run, however often it is asked.
      #
      # #fetch_original_title and #spanish_original? ask TMDB exactly the same
      # thing, and the notifier asks about every screening of a film rather
      # than every film, so the same query went out two or three times over
      # before this. A client is built once per run, which makes it the right
      # lifetime for the answers.
      def search(title, year = nil)
        @results[[title, year]] ||= fetch(title, year)
      end

      # Cached by id for the same reason as #search: a film showing at several
      # cinemas is asked about once per cinema.
      def details(id)
        @details[id] ||= get_json("#{DOMAIN}/3/movie/#{id}?#{URI.encode_www_form(api_key: @api_key)}") || {}
      end

      def fetch(title, year)
        query = URI.encode_www_form(query: title, language: "es-ES", api_key: @api_key)
        query += "&year=#{year}" if year
        # An empty list rather than nil: "TMDB had nothing for us" and "TMDB
        # would not answer" mean the same thing to every caller here, and a nil
        # would have each of them checking for it.
        get_json("#{DOMAIN}/3/search/movie?#{query}")&.dig("results") || []
      end

      def get_json(url)
        response = @http.get(url)
        response.code == "200" ? JSON.parse(response.body) : nil
      end
    end
  end
end
