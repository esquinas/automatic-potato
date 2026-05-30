# frozen_string_literal: true

Rating = Data.define(:score) do
  NULL = new(score: nil).freeze

  def self.null = NULL
  def present?  = !score.nil?
  def formatted = score && format("★ %.1f", score)
end
