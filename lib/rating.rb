# frozen_string_literal: true

Rating = Data.define(:score) do
  def self.null = new(score: nil).freeze
  def formatted = score && format("★ %.1f", score)
end
