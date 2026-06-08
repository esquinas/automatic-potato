# frozen_string_literal: true

require_relative "../screening_collection"

module Services
  class FilmSessionGrouper
    def initialize(movies_db)
      @movies_db = movies_db
    end

    def group(sessions)
      unique_films = sessions.map(&:film).uniq

      unique_films.map do |film|
        film_sessions = sessions.select { |s| s.film == film }
        ScreeningCollection.new(film, @movies_db.rating_for(film), film_sessions)
      end
    end
  end
end
