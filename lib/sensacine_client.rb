# frozen_string_literal: true

require "json"
require_relative "http_client"
require_relative "film"
require_relative "screening_session"

# One theatre-day of SensaCine's internal JSON, turned into ScreeningSessions.
#
# It answers with every screening it finds, original version or not, and marks
# each one; deciding what to do with a dubbed screening is the notifier's job.
# The endpoint lists only screenings still on sale, so a day drains as its
# programme runs and an empty answer means expired, not absent — see CLAUDE.md.
class SensacineClient
  include HttpClient

  DOMAIN             = "https://www.sensacine.com"
  VO_BUCKETS         = %w[original original_st original_sme local local_st local_sme].freeze
  UNFILTERED_BUCKETS = (VO_BUCKETS + %w[dubbed dubbed_st dubbed_sme]).freeze

  def initialize(**) = nil

  HEADERS = {
    "User-Agent"      => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Accept"          => "application/json",
    "Accept-Language" => "es-ES,es;q=0.9",
    "Referer"         => "#{DOMAIN}/cines/cine/"
  }.freeze

  def fetch_theater_movie_sessions(date:, theater_id:)
    url = "#{DOMAIN}/_/showtimes/theater-#{theater_id}/d-#{date}/"
    day = get_page(url)
    return [] unless day

    results = day["results"].to_a + later_pages(url, day.dig("pagination", "totalPages").to_i)
    parse_sessions(results, date)
  end

  private

  # The feed carries the film's own year under movie.data and the dates it
  # reached cinemas under movie.releases[]. The production year is the one TMDB
  # files a film under, so it is the one worth searching by; the earliest
  # release is the fallback for an entry that arrives without one.
  def year_of(entry)
    entry.dig("movie", "data", "productionYear") || earliest_release_year(entry.dig("movie", "releases") || [])
  end

  def earliest_release_year(releases)
    releases.filter_map { |release| release.dig("releaseDate", "date").to_s[/\A\d{4}/] }.min&.to_i
  end

  # One request, and the two ways the endpoint declines to answer: a non-200,
  # and the healthy "nothing left to book" body, which carries error: true, a
  # message of "next.showtime.on" and the date of the next screening.
  def get_page(url)
    puts "GET #{url}"
    resp = http_get(url, HEADERS)
    code = resp.code
    puts "HTTP #{code}"
    return nil unless code == "200"

    parsed = JSON.parse(resp.body)
    return parsed unless parsed["error"]

    puts "  API error: #{parsed["message"]} (nextDate: #{parsed["nextDate"]})"
    nil
  end

  # A busy day is split into pages of ten. Reading stops at the first page that
  # adds nothing, and stops asking too — lazily, so a provider that falls over
  # halfway through costs the rest of that day and no more requests. The page
  # number goes in the query string: the /p-{n}/ path segment the rest of the
  # site uses makes this endpoint answer with empty results.
  def later_pages(url, total_pages)
    (2..total_pages).lazy
                    .map { |page| get_page("#{url}?page=#{page}")&.dig("results") }
                    .take_while { |results| !results.to_a.empty? }
                    .force
                    .flatten(1)
  end

  def parse_sessions(results, date)
    results.flat_map { |entry| sessions_for(entry, date) }
  end

  def sessions_for(entry, date)
    film = Film.new(localized_title: entry.dig("movie", "title") || "(untitled)", year: year_of(entry))

    UNFILTERED_BUCKETS.flat_map do |bucket|
      (entry.dig("showtimes", bucket) || []).filter_map { |showtime| screening(showtime, bucket, film, date) }
    end
  end

  # Both signals count. The bucket alone is not enough: SensaCine misfiles some
  # subtitled prints under "dubbed", where only diffusionVersion gives them
  # away — that is how Yelmo's VOSE screenings arrive.
  def screening(showtime, bucket, film, date)
    starts_at = showtime["startsAt"]&.slice(11, 5)
    return nil unless starts_at

    ScreeningSession.new(
      film:              film,
      date:              date,
      starts_at:         starts_at,
      original_version?: VO_BUCKETS.include?(bucket) || showtime["diffusionVersion"] == "ORIGINAL"
    )
  end
end
