# frozen_string_literal: true

require "date"

class PlainMessage
  def render_film(presentation)
    parts = [presentation.film.localized_title]
    parts << "(#{presentation.film.title})" if presentation.film.title && presentation.film.title.downcase != presentation.film.localized_title.downcase
    parts << presentation.rating.to_s.strip
    title_line = parts.join(" ").strip

    showtime_lines = if presentation.full_week
      times = presentation.date_time_structure[:times]
      ["All week: #{presentation.date_time_structure[:range_start]} → #{presentation.date_time_structure[:range_end]}: #{times.join(", ")}"]
    else
      dates = presentation.date_time_structure[:dates]
      dates.map { |date, times| "#{weekday(date)}: #{times.join(", ")}" }
    end

    ["", title_line, *showtime_lines]
  end

  private

  def weekday(date_str)
    Date.parse(date_str).strftime("%a")
  end
end
