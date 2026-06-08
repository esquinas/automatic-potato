# frozen_string_literal: true

require "date"

class HtmlMessage
  def render_film(presentation)
    parts = ["<b>#{presentation.film.localized_title}</b>"]
    parts << "<i>(#{presentation.film.title})</i>" if presentation.film.title && presentation.film.title.downcase != presentation.film.localized_title.downcase
    parts << presentation.rating
    title_line = parts.join(" ").strip

    showtime_lines = if presentation.full_week
      times = presentation.date_time_structure[:times]
      max_time_width = times.map(&:length).max
      formatted_times = times.map { |t| t.rjust(max_time_width) }
      ["<pre>• All week: #{presentation.date_time_structure[:range_start]} → #{presentation.date_time_structure[:range_end]}\n  #{formatted_times.join(", ")}</pre>"]
    else
      dates = presentation.date_time_structure[:dates]
      all_times = dates.values.flatten.sort.uniq
      max_time_width = all_times.map(&:length).max
      lines = dates.map do |date, times|
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
