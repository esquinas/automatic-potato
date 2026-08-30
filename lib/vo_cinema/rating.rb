# frozen_string_literal: true

module VoCinema
  # What TMDB thinks of a film, or Rating.null when it would not commit.
  #
  # A NullObject: both kinds answer to_s and to_str, so a caller pushes one into
  # a parts array and joins it without ever asking whether there is a score.
  Rating = Data.define(:score) do
    def self.null = new(score: nil).freeze
    def to_s   = score ? format("★ %.1f", score) : ""
    def to_str = to_s
  end
end
