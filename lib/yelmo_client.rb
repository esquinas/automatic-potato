# frozen_string_literal: true

require "json"
require_relative "http_client"
require_relative "film"
require_relative "screening_session"

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
    city_key, cinema_key = theater_id.split("/", 2)
    sessions_cache(city_key, cinema_key)[date] || []
  end

  private

  def sessions_cache(city_key, cinema_key)
    @cache ||= {}
    @cache["#{city_key}/#{cinema_key}"] ||= fetch_and_index(city_key, cinema_key)
  end

  def fetch_and_index(city_key, cinema_key)
    url  = "#{DOMAIN}/now-playing.aspx/GetNowPlaying"
    body = JSON.generate({ cityKey: city_key })

    puts "POST #{url} (cityKey=#{city_key})"
    resp = http_post(url, body, HEADERS)
    puts "HTTP #{resp.code}"
    return {} unless resp.code == "200"

    cinemas = JSON.parse(resp.body).dig("d", "Cinemas") || []
    cinema  = cinemas.find { |entry| entry["Key"] == cinema_key }
    unless cinema
      available = cinemas.map { |entry| entry["Key"] }
      puts "  Yelmo: cinema #{cinema_key.inspect} not found (available: #{available.inspect})"
      return {}
    end

    index_sessions(cinema)
  end

  def index_sessions(cinema)
    by_date = Hash.new { |hash, key| hash[key] = [] }
    (cinema["Dates"] || []).each do |date_entry|
      date = parse_date(date_entry["FilterDate"])
      (date_entry["Movies"] || []).each do |movie|
        sessions_for_movie(movie, date).each { |session| by_date[date] << session }
      end
    end
    by_date
  end

  def sessions_for_movie(movie, date)
    film = Film.new(localized_title: movie["Title"] || "(untitled)", year: nil)
    (movie["Formats"] || []).flat_map do |format|
      vo = VO_LANGUAGES.any? { |lang| format["Language"].to_s.include?(lang) }
      (format["Showtimes"] || []).filter_map do |showtime|
        starts_at = showtime["Time"]&.slice(0, 5)
        next unless starts_at

        ScreeningSession.new(
          film:              film,
          date:              date,
          starts_at:         starts_at,
          original_version?: vo
        )
      end
    end
  end

  def parse_date(filter_date)
    ms = filter_date.to_s[/\d+/].to_i
    Time.at(ms / 1000).utc.strftime("%Y-%m-%d")
  end
end
