# frozen_string_literal: true

require "date"

class WeeklyNotifier
  TELEGRAM_MAX_MSG_CHARS = 3800
  WEEK_DAYS              = 7

  def initialize(showtimes:, movies_db:, messenger:, cinemas:, yelmo_showtimes: nil)
    @showtimes       = showtimes
    @movies_db       = movies_db
    @messenger       = messenger
    @cinemas         = cinemas
    @yelmo_showtimes = yelmo_showtimes
  end

  def run(today: Date.today)
    lines           = []
    nothing_left_at = []

    @cinemas.each do |cinema|
      sessions = collect_sessions(cinema, today)

      if sessions.empty?
        nothing_left_at << cinema["name"]
        next
      end

      lines.concat(render_cinema(cinema, sessions, today))
      lines << ""
    end

    lines.concat(closing_notes(nothing_left_at))

    message = lines.join("\n").strip
    message = "#{message[0, TELEGRAM_MAX_MSG_CHARS]}\n... (truncated)" if message.length > TELEGRAM_MAX_MSG_CHARS

    @messenger.send_message(message)
    puts "Sent #{message.length} chars"
  end

  private

  # Both providers list only screenings you could still buy a ticket for, so a
  # day drains as its programme runs and a venue that came back empty has not
  # necessarily programmed nothing — its screenings may already have been
  # shown. Neither line below claims otherwise, and neither should anything
  # that replaces them: see "An empty day means expired, not absent" in
  # CLAUDE.md.
  def closing_notes(nothing_left_at)
    notes = []
    notes += ["Nothing left to catch this week at: #{nothing_left_at.join(", ")}", ""] unless nothing_left_at.empty?
    notes << "Today lists only what is still to come; earlier screenings have already been shown."
    notes
  end

  def collect_sessions(cinema, today)
    sensacine = WEEK_DAYS.times.flat_map do |offset|
      date = (today + offset).to_s
      @showtimes.fetch_theater_movie_sessions(date: date, theater_id: cinema["id"])
    end

    if @yelmo_showtimes && cinema["yelmo_id"]
      yelmo = WEEK_DAYS.times.flat_map do |offset|
        date = (today + offset).to_s
        @yelmo_showtimes.fetch_theater_movie_sessions(date: date, theater_id: cinema["yelmo_id"])
      end
      sensacine = merge_sessions(sensacine, yelmo)
    end

    return sensacine unless cinema["check_vo"]

    sensacine.select { |s| s.original_version? || spanish_original?(s.film) }
  end

  # A film with no dubbed/subtitled distinction (e.g. a Spanish production) never
  # gets tagged VO by a provider, since there's nothing to dub or subtitle — its
  # only screening IS the original version. TMDB's original_language is the only
  # way to tell that apart from a foreign film dubbed into Spanish.
  def spanish_original?(film)
    @spanish_original_cache ||= {}
    @spanish_original_cache.fetch(film) { @spanish_original_cache[film] = @movies_db.spanish_original?(film) }
  end

  def merge_sessions(primary, secondary)
    by_key = Hash.new { |h, k| h[k] = [] }
    (primary + secondary).each do |s|
      by_key[[s.date, s.starts_at, s.film.localized_title.downcase.strip]] << s
    end
    by_key.values.map { |group| group.find(&:original_version?) || group.first }
  end

  def render_cinema(cinema, sessions, today)
    week_end     = (today + WEEK_DAYS - 1).to_s
    unique_films = sessions.map(&:film).uniq

    unique_films.each { |film| film.title = @movies_db.fetch_original_title(film) }

    film_lines = unique_films.flat_map do |film|
      render_film(film, @movies_db.rating_for(film), sessions.select { |s| s.film == film })
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
