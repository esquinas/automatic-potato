# frozen_string_literal: true

module Services
  class FilmEnricher
    def initialize(movies_db)
      @movies_db = movies_db
    end

    def enrich(sessions)
      unique_films = sessions.map(&:film).uniq
      unique_films.each { |film| film.title = @movies_db.fetch_original_title(film) }
      sessions
    end
  end
end
