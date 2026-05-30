# frozen_string_literal: true

Rating = Data.define(:score) do
  def self.null = new(score: nil).freeze
  def to_s   = score ? format("★ %.1f", score) : ""
  def to_str = to_s
end
