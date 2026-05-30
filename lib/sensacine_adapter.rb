# frozen_string_literal: true

require "json"
require_relative "http_client"
require_relative "film"
require_relative "screening_session"

class SensacineAdapter
  include HttpClient

  VO_BUCKETS         = %w[original local].freeze
  UNFILTERED_BUCKETS = %w[original local dubbed].freeze

  HEADERS = {
    "User-Agent"      => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Accept"          => "application/json",
    "Accept-Language" => "es-ES,es;q=0.9",
    "Referer"         => "https://www.sensacine.com/cines/cine/"
  }.freeze

  def fetch_theater_movie_sessions(date:, theater_id:)
    url = "https://www.sensacine.com/_/showtimes/theater-#{theater_id}/d-#{date}/p-1/"

    puts "GET #{url}"
    resp = http_get(url, HEADERS)
    puts "HTTP #{resp.code}"
    return [] unless resp.code == "200"

    parse_sessions(JSON.parse(resp.body)["results"] || [], date)
  end

  private

  def parse_sessions(results, date)
    results.flat_map do |entry|
      film = Film.new(
        localized_title: entry.dig("movie", "title") || "(untitled)",
        year:            entry.dig("movie", "release", "year")
      )

      UNFILTERED_BUCKETS.flat_map do |bucket|
        original_version = VO_BUCKETS.include?(bucket)

        (entry.dig("showtimes", bucket) || []).filter_map do |showtime|
          starts_at = showtime["startsAt"]&.slice(11, 5)
          next unless starts_at

          ScreeningSession.new(
            film:              film,
            date:              date,
            starts_at:         starts_at,
            original_version?: original_version
          )
        end
      end
    end
  end
end
