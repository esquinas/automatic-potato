# frozen_string_literal: true

module VoCinema
  # One screening: which film, which day, what time, and whether it is the print
  # in the original language. Fully resolved when it is built, never mutated.
  #
  # Matching two providers' records of the same screening is Reconciliation's
  # job: the day and the minute are read straight off here, and which film they
  # describe is Film#same_film_as?.
  ScreeningSession = Data.define(:film, :date, :starts_at, :original_version?)
end
