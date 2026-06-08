# frozen_string_literal: true

require "date"
require_relative "constants"

class HtmlMessage
  def render_film(film, rating, sessions)
    parts = ["<b>#{film.localized_title}</b>"]
    parts << "<i>(#{film.title})</i>" if film.title && film.title.downcase != film.localized_title.downcase
    parts << rating
    title_line = parts.join(" ").strip

    dates_map = sessions
      .group_by(&:date)
      .transform_values { |ss| ss.map(&:starts_at).sort.uniq }
      .sort.to_h

    showtime_lines = if dates_map.keys.length == WEEK_DAYS
      all_times = dates_map.values.flatten.sort.uniq
      max_time_width = all_times.map(&:length).max
      formatted_times = all_times.map { |t| t.rjust(max_time_width) }
      ["<pre>• All week: #{dates_map.keys.min} → #{dates_map.keys.max}\n  #{formatted_times.join(", ")}</pre>"]
    else
      all_times = dates_map.values.flatten.sort.uniq
      max_time_width = all_times.map(&:length).max
      lines = dates_map.map do |date, times|
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
