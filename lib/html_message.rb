# frozen_string_literal: true

require "date"
require_relative "screening_collection"

class HtmlMessage
  def render_film(collection)
    parts = ["<b>#{collection.film.localized_title}</b>"]
    parts << "<i>(#{collection.film.title})</i>" if collection.film.title && collection.film.title.downcase != collection.film.localized_title.downcase
    parts << collection.rating
    title_line = parts.join(" ").strip

    showtime_lines = if collection.full_week?
      all_times = collection.all_times
      max_time_width = all_times.map(&:length).max
      formatted_times = all_times.map { |t| t.rjust(max_time_width) }
      ["<pre>• All week: #{collection.dates_map.keys.min} → #{collection.dates_map.keys.max}\n  #{formatted_times.join(", ")}</pre>"]
    else
      all_times = collection.all_times
      max_time_width = all_times.map(&:length).max
      lines = collection.dates_map.map do |date, times|
        formatted_times = times.map { |t| t.rjust(max_time_width) }
        "• #{weekday(date)} → #{formatted_times.join(", ")}"
      end
      ["<pre>#{lines.join("\n")}</pre>"]
    end

    ["", title_line, *showtime_lines]
  end

  private

  def weekday(date_str)
    Date.parse(date_str).strftime("%a")
  end
end
