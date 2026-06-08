# frozen_string_literal: true

module Presenters
  class FilmPresentation
    attr_reader :film, :rating, :full_week, :date_time_structure

    def initialize(film, rating, full_week, date_time_structure)
      @film = film
      @rating = rating
      @full_week = full_week
      @date_time_structure = date_time_structure
    end

    def self.from_screening_collection(collection)
      if collection.full_week?
        date_time_structure = {
          range_start: collection.dates_map.keys.min,
          range_end:   collection.dates_map.keys.max,
          times:       collection.all_times
        }
      else
        date_time_structure = { dates: collection.dates_map }
      end

      new(collection.film, collection.rating, collection.full_week?, date_time_structure)
    end
  end
end
