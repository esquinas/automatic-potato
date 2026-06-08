# frozen_string_literal: true

require_relative "../rating"

module Mappers
  class TmdbMovieMapper
    AMBIGUITY_RATIO = 2.0

    def extract_title(results)
      results&.first&.dig("original_title")
    end

    def extract_rating(results)
      return Rating.null if results.nil? || results.empty?

      top    = results[0]
      second = results[1]

      return Rating.null if top["vote_count"].to_i.zero?

      top_score    = top["vote_average"].to_f
      second_score = (second&.dig("vote_average") || 0).to_f
      return Rating.null if second_score > 0 && top_score / second_score < AMBIGUITY_RATIO

      Rating.new(score: top_score)
    end
  end
end
