# frozen_string_literal: true

require "date"

class DigestFormatter
  WEEK_DAYS = 7

  def format(cinema_digests, today:)
    lines         = []
    no_vo_cinemas = []

    cinema_digests.each do |digest|
      if digest.sessions.empty?
        no_vo_cinemas << digest.cinema["name"]
        next
      end

      lines.concat(render_cinema(digest, today))
      lines << ""
    end

    unless no_vo_cinemas.empty?
      lines << "The following venues had no VO sessions: #{no_vo_cinemas.join(", ")}"
      lines << ""
    end

    lines.join("\n").strip
  end

  private

  def render_cinema(digest, today)
    cinema   = digest.cinema
    sessions = digest.sessions
    ratings  = digest.ratings
    week_end = today + WEEK_DAYS - 1

    unique_films = sessions.map(&:film).uniq

    film_lines = unique_films.flat_map do |film|
      render_film(film, ratings[film], sessions.select { |s| s.film == film })
    end

    [cinema_header(cinema, "#{cinema["name"]} — #{today} → #{week_end}"), *film_lines]
  end

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

  def cinema_header(cinema, label)
    cinema["url"] ? "<b><a href=\"#{cinema["url"]}\">#{label}</a></b>" : "<b>#{label}</b>"
  end

  def weekday(date_str)
    Date.parse(date_str).strftime("%a")
  end
end
