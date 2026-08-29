# frozen_string_literal: true

require "json"
require_relative "http_client"
require_relative "film"
require_relative "screening_session"

# The authoritative source for what is subtitled at Yelmo Ocimax Gijón.
#
# SensaCine files Yelmo's VOSE prints under "dubbed"; Yelmo's own listings tag
# them properly. One request brings back the whole city for the whole week, so
# it is cached and re-read day by day.
class YelmoClient
  include HttpClient

  DOMAIN       = "https://www.yelmocines.es"
  VO_LANGUAGES = %w[VOSE SUBTITULAD V.O.S.].freeze

  HEADERS = {
    "Content-Type"     => "application/json; charset=UTF-8",
    "X-Requested-With" => "XMLHttpRequest",
    "Accept"           => "application/json, text/javascript, */*; q=0.01",
    "Referer"          => "#{DOMAIN}/cartelera",
    "User-Agent"       => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
  }.freeze

  def initialize(**) = nil

  def fetch_theater_movie_sessions(date:, theater_id:)
    sessions_cache(theater_id)[date] || []
  end

  private

  def sessions_cache(theater_id)
    @cache ||= {}
    @cache[theater_id] ||= fetch_and_index(theater_id)
  end

  def fetch_and_index(theater_id)
    cinema = find_cinema(theater_id)
    return {} unless cinema

    by_date = Hash.new { |days, date| days[date] = [] }
    (cinema["Dates"] || []).each do |day|
      date = parse_date(day["FilterDate"])
      by_date[date].concat(sessions_on(day, date))
    end
    by_date
  end

  # A theater_id is "city-key/cinema-key": Yelmo is asked about the city and
  # the cinema is picked out of the answer.
  def find_cinema(theater_id)
    city_key, cinema_key = theater_id.split("/", 2)
    cinemas              = cinemas_in(city_key)

    cinemas.find { |cinema| cinema["Key"] == cinema_key } || missing(cinema_key, cinemas)
  end

  # Nothing to add when the request itself failed; that is already logged.
  def missing(cinema_key, cinemas)
    return nil if cinemas.empty?

    puts "  Yelmo: cinema #{cinema_key.inspect} not found (available: #{cinemas.map { |known| known["Key"] }.inspect})"
    nil
  end

  def cinemas_in(city_key)
    url = "#{DOMAIN}/now-playing.aspx/GetNowPlaying"

    puts "POST #{url} (cityKey=#{city_key})"
    resp = http_post(url, JSON.generate({ cityKey: city_key }), HEADERS)
    code = resp.code
    puts "HTTP #{code}"
    return [] unless code == "200"

    JSON.parse(resp.body).dig("d", "Cinemas") || []
  end

  # One day's programme. Yelmo nests it three deep: each film is offered in
  # several formats — dubbed, subtitled, 3D — and each format has its own list
  # of times, so the language tag that decides original_version? belongs to the
  # format rather than to the film.
  def sessions_on(day, date)
    (day["Movies"] || []).flat_map do |movie|
      film = Film.new(localized_title: movie["Title"] || "(untitled)", year: nil)

      (movie["Formats"] || []).flat_map { |format| screenings_of(film, format, date) }
    end
  end

  def screenings_of(film, format, date)
    original_version = VO_LANGUAGES.any? { |tag| format["Language"].to_s.include?(tag) }

    (format["Showtimes"] || []).filter_map do |showtime|
      starts_at = showtime["Time"]&.slice(0, 5)
      next unless starts_at

      ScreeningSession.new(film: film, date: date, starts_at: starts_at, original_version?: original_version)
    end
  end

  def parse_date(filter_date)
    ms = filter_date.to_s[/\d+/].to_i
    Time.at(ms / 1000).utc.strftime("%Y-%m-%d")
  end
end
