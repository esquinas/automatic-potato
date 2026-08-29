# frozen_string_literal: true

# One screening: which film, which day, what time, and whether it is the print
# in the original language. Fully resolved when it is built, never mutated.
ScreeningSession = Data.define(:film, :date, :starts_at, :original_version?) do
  # What makes two providers' records the same screening. Ocimax is listed by
  # both SensaCine and Yelmo, and this is how their accounts are matched up.
  def slot = [date, starts_at, film.key]
end
