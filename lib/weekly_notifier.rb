# frozen_string_literal: true

require "date"
require_relative "constants"
require_relative "screening_collection"
require_relative "html_message"

class WeeklyNotifier
  TELEGRAM_MAX_MSG_CHARS = 3800

  def initialize(showtimes:, movies_db:, messenger:, cinemas:, message_renderer: HtmlMessage.new)
    @showtimes         = showtimes
    @movies_db         = movies_db
    @messenger         = messenger
    @cinemas           = cinemas
    @message_renderer  = message_renderer
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
    message = "#{message[0, TELEGRAM_MAX_MSG_CHARS]}\n... (truncated)" if message.length > TELEGRAM_MAX_MSG_CHARS

    @messenger.send_message(message)
    puts "Sent #{message.length} chars"
  end

  private

  def collect_sessions(cinema, today)
    WEEK_DAYS.times.flat_map do |offset|
      date     = (today + offset).to_s
      sessions = @showtimes.fetch_theater_movie_sessions(date: date, theater_id: cinema["id"])
      cinema["check_vo"] ? sessions.select(&:original_version?) : sessions
    end
  end

  def render_cinema(cinema, sessions, today)
    week_end     = (today + WEEK_DAYS - 1).to_s
    unique_films = sessions.map(&:film).uniq

    unique_films.each { |film| film.title = @movies_db.fetch_original_title(film) }

    film_lines = unique_films.flat_map do |film|
      collection = ScreeningCollection.new(film, @movies_db.rating_for(film), sessions.select { |s| s.film == film })
      @message_renderer.render_film(collection)
    end

    [cinema_header(cinema, "#{cinema["name"]} — #{today} → #{week_end}"), *film_lines]
  end

  def cinema_header(cinema, label)
    cinema["url"] ? "<b><a href=\"#{cinema["url"]}\">#{label}</a></b>" : "<b>#{label}</b>"
  end
end
