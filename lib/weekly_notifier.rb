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
    lines         = []
    no_vo_cinemas = []

    @cinemas.each do |cinema|
      sessions = collect_sessions(cinema, today)

      if sessions.empty?
        no_vo_cinemas << cinema["name"]
        next
      end

      lines.concat(render_cinema(cinema, sessions, today))
      lines << ""
    end

    unless no_vo_cinemas.empty?
      lines << "The following venues had no VO sessions: #{no_vo_cinemas.join(", ")}"
      lines << ""
    end

    message = lines.join("\n").strip
    len     = message.length
    message = "#{message[0, TELEGRAM_MAX_MSG_CHARS]}\n... (truncated)" if len > TELEGRAM_MAX_MSG_CHARS

    @messenger.send_message(message)
    puts "Sent #{message.length} chars"
  end

  private

  def collect_sessions(cinema, today)
    sessions = sessions_for_week(@showtimes, cinema["id"], today)

    if @yelmo_showtimes && cinema["yelmo_id"]
      yelmo    = sessions_for_week(@yelmo_showtimes, cinema["yelmo_id"], today)
      sessions = merge_sessions(sessions, yelmo)
    end

    cinema["check_vo"] ? sessions.select(&:original_version?) : sessions
  end

  def sessions_for_week(client, theater_id, today)
    WEEK_DAYS.times.flat_map do |offset|
      client.fetch_theater_movie_sessions(date: (today + offset).to_s, theater_id: theater_id)
    end
  end

  def merge_sessions(primary, secondary)
    by_key = Hash.new { |hash, key| hash[key] = [] }
    (primary + secondary).each do |session|
      by_key[[session.date, session.starts_at, session.film.localized_title.downcase.strip]] << session
    end
    by_key.values.map { |group| group.find(&:original_version?) || group.first }
  end

  def render_cinema(cinema, sessions, today)
    week_end     = (today + WEEK_DAYS - 1).to_s
    unique_films = sessions.map(&:film).uniq

    unique_films.each { |film| film.title = @movies_db.fetch_original_title(film) }

    film_lines = unique_films.flat_map do |film|
      render_film(film, @movies_db.rating_for(film), sessions.select { |session| session.film == film })
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

    all_times      = dates_map.values.flatten.sort.uniq
    max_time_width = all_times.map(&:length).max

    showtime_lines = if dates_map.keys.length == WEEK_DAYS
      formatted = all_times.map { |time| time.rjust(max_time_width) }
      ["<pre>• All week: #{dates_map.keys.min} → #{dates_map.keys.max}\n  #{formatted.join(", ")}</pre>"]
    else
      lines = dates_map.map do |date, times|
        formatted = times.map { |time| time.rjust(max_time_width) }
        "• #{weekday(date)} → #{formatted.join(", ")}"
      end
      ["<pre>#{lines.join("\n")}</pre>"]
    end

    ["", title_line, *showtime_lines]
  end

  def cinema_header(cinema, label)
    url = cinema["url"]
    url ? "<b><a href=\"#{url}\">#{label}</a></b>" : "<b>#{label}</b>"
  end

  def weekday(date_str)
    Date.parse(date_str).strftime("%a")
  end
end
