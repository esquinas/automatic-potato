# frozen_string_literal: true

require "date"
require_relative "constants"

class PlainMessage
  def render_film(film, rating, sessions)
    parts = [film.localized_title]
    parts << "(#{film.title})" if film.title && film.title.downcase != film.localized_title.downcase
    parts << rating.to_s.strip
    title_line = parts.join(" ").strip

    dates_map = sessions
      .group_by(&:date)
      .transform_values { |ss| ss.map(&:starts_at).sort.uniq }
      .sort.to_h

    showtime_lines = if dates_map.keys.length == WEEK_DAYS
      all_times = dates_map.values.flatten.sort.uniq
      ["All week: #{dates_map.keys.min} → #{dates_map.keys.max}: #{all_times.join(", ")}"]
    else
      dates_map.map { |date, times| "#{weekday(date)}: #{times.join(", ")}" }
    end

    ["", title_line, *showtime_lines]
  end

  private

  def weekday(date_str)
    Date.parse(date_str).strftime("%a")
  end
end
