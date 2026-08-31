# frozen_string_literal: true

module VoCinema
  module Movies
    # What TMDB knows about a film the cinemas listed in Spanish: its original
    # title, its rating, and whether it is a Spanish production.
    #
    # Three pure queries — nothing here mutates a Film. WeeklyNotifier owns that.
    # Putting the question to TMDB is Search's job; this class only decides what
    # comes back means.
    class Tmdb
      DOMAIN = "https://api.themoviedb.org"

      # How far ahead of the runner-up the best match has to be before its score
      # is worth printing.
      AMBIGUITY_RATIO = 2.0

      def initialize(api_key: ENV.fetch("TMDB_API_KEY"), http: Http::Client.new)
        @search = Search.new(api_key: api_key, http: http)
      end

      def fetch_original_title(film) = best_match_for(film)&.dig("original_title")

      def spanish_original?(film) = best_match_for(film)&.dig("original_language") == "es"

      # Asked by the original title once that is known, because it is the one
      # TMDB itself files the film under.
      def rating_for(film)
        score = confident_score(@search.results_for(film.title || film.localized_title, film.year))

        score ? Rating.new(score: score) : Rating.null
      end

      private

      # Searched for by the title the cinema printed, which is all a provider
      # knows the film by.
      def best_match_for(film) = @search.results_for(film.localized_title, film.year).first

      # TMDB always answers something, so a score is only worth printing when the
      # best match is clearly the film we meant: somebody has to have voted on
      # it, and it has to beat the runner-up clearly enough that the two are not
      # plausibly the same search gone wrong.
      def confident_score(results)
        best, runner_up = results
        return nil unless best && best["vote_count"].to_i.positive?

        score = best["vote_average"].to_f
        score unless too_close_to_call?(score, runner_up)
      end

      def too_close_to_call?(score, runner_up)
        runner_up_score = runner_up&.dig("vote_average").to_f

        runner_up_score.positive? && score / runner_up_score < AMBIGUITY_RATIO
      end
    end
  end
end
