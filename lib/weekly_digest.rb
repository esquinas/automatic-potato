# frozen_string_literal: true

# The fully resolved weekly programme, ready to be rendered by any Formatter.

FilmListing = Data.define(:film, :rating, :sessions) do
  def showtimes_by_date
    sessions
      .group_by(&:date)
      .transform_values { |group| group.map(&:starts_at).sort.uniq }
      .sort.to_h
  end
end

CinemaProgram = Data.define(:cinema, :listings)

WeeklyDigest = Data.define(:from, :to, :programs, :quiet_cinemas) do
  def days = (to - from).to_i + 1
end
