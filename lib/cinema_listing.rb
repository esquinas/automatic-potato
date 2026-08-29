# frozen_string_literal: true

require_relative "rating"

# One cinema's week, as the digest is about to print it: the venue as it is
# configured, the screenings that survived filtering, and the rating for each
# film. Films arrive already enriched — WeeklyNotifier owns that lifecycle —
# so nothing here needs to ask TMDB anything.
CinemaListing = Data.define(:cinema, :sessions, :ratings) do
  def name = cinema["name"]
  def url  = cinema["url"]

  # In the order the providers first mentioned them.
  def films = sessions.map(&:film).uniq

  def sessions_for(film) = sessions.select { |session| session.film == film }

  # A film TMDB would not commit on contributes no rating rather than a gap.
  def rating_for(film) = ratings.fetch(film, Rating.null)
end
