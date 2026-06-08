# frozen_string_literal: true

require "date"
require_relative "screening_collection"

class PlainMessage
  def render_film(collection)
    parts = [collection.film.localized_title]
    parts << "(#{collection.film.title})" if collection.film.title && collection.film.title.downcase != collection.film.localized_title.downcase
    parts << collection.rating.to_s.strip
    title_line = parts.join(" ").strip

    showtime_lines = if collection.full_week?
      all_times = collection.all_times
      ["All week: #{collection.dates_map.keys.min} → #{collection.dates_map.keys.max}: #{all_times.join(", ")}"]
    else
      collection.dates_map.map { |date, times| "#{weekday(date)}: #{times.join(", ")}" }
    end

    ["", title_line, *showtime_lines]
  end

  private

  def weekday(date_str)
    Date.parse(date_str).strftime("%a")
  end
end
