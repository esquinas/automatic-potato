# frozen_string_literal: true

require "json"

module VoCinema
  module Showtimes
    # Fetches a theatre's day from SensaCine's internal JSON API.
    #
    # This class deals only in requests: which URL, how many pages, and the two
    # ways the endpoint declines to answer. Turning a payload into screenings
    # is Day's job.
    #
    # The endpoint lists only screenings still on sale, so a day drains as its
    # programme runs and an empty answer means expired, not absent — see
    # CLAUDE.md.
    class Sensacine
      DOMAIN = "https://www.sensacine.com"

      # The browser manners every scraped endpoint needs, plus the two this one
      # insists on: it answers 403 to a request that does not look like its own
      # listing page asking.
      HEADERS = Http::Client::BROWSER.merge(
        "Accept"  => "application/json",
        "Referer" => "#{DOMAIN}/cines/cine/"
      ).freeze

      def initialize(http: Http::Client.new(headers: HEADERS))
        @http = http
      end

      # How the run log names this provider when reporting what the providers
      # disagreed about. Spelled the way SensaCine spells itself.
      def name = "SensaCine"

      # Nothing to say about a venue SensaCine does not list.
      def sessions_for(cinema, date)
        return [] unless cinema.sensacine_id

        url  = day_url(cinema.sensacine_id, date)
        page = get_page(url)
        return [] unless page

        Day.new(page["results"].to_a + later_pages(url, page), date).sessions
      end

      private

      def day_url(theater_id, date) = "#{DOMAIN}/_/showtimes/theater-#{theater_id}/d-#{date}/"

      # A non-200, and the healthy "nothing left to book" body, which carries
      # error: true, a message of "next.showtime.on" and the date of the next
      # screening. Both mean the same to the caller; only one is worth logging.
      def get_page(url)
        response = @http.get(url)
        return nil unless response.code == "200"

        parsed = JSON.parse(response.body)
        return parsed unless parsed["error"]

        puts "  API error: #{parsed["message"]} (nextDate: #{parsed["nextDate"]})"
        nil
      end

      # A busy day is split into pages of ten. Reading stops at the first page
      # that adds nothing, and stops asking too — lazily, so a provider that
      # falls over halfway through costs the rest of that day and no more
      # requests. The page number goes in the query string: the /p-{n}/ path
      # segment the rest of the site uses makes this endpoint answer empty.
      def later_pages(url, first_page)
        (2..first_page.dig("pagination", "totalPages").to_i)
          .lazy
          .map { |page| get_page("#{url}?page=#{page}")&.dig("results") }
          .take_while { |results| !results.to_a.empty? }
          .force
          .flatten(1)
      end
    end
  end
end
