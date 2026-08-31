# frozen_string_literal: true

require "json"

module VoCinema
  module Showtimes
    class Sensacine
      # One day's listing entries, however many pages SensaCine split them over.
      #
      # A busy day comes back ten entries at a time, with pagination.totalPages
      # saying how many there are. Reading stops at the first page that adds
      # nothing, and stops asking too — lazily, so an endpoint that falls over
      # halfway through a day costs the rest of that day and no more requests.
      #
      # The page number goes in the query string: the /p-{n}/ path segment the
      # rest of the site uses makes this endpoint answer with empty results.
      class Pages
        def initialize(http, url)
          @http = http
          @url  = url
        end

        # Empty for a day the endpoint would not, or had nothing left to, answer.
        def entries
          first_page = get(@url)
          return [] unless first_page

          first_page["results"].to_a + entries_after(first_page)
        end

        private

        def entries_after(first_page)
          (2..first_page.dig("pagination", "totalPages").to_i)
            .lazy
            .map { |number| get("#{@url}?page=#{number}")&.dig("results") }
            .take_while { |results| !results.to_a.empty? }
            .force
            .flatten(1)
        end

        # Nil for either way the endpoint declines: a non-200, or the healthy
        # "nothing left to book" body below.
        def get(url)
          response = @http.get(url)
          return nil unless response.code == "200"

          page = JSON.parse(response.body)
          page["error"] ? nothing_left_to_book(page) : page
        end

        # SensaCine says a day is spent with error: true, a message of
        # "next.showtime.on", and the date of the next screening. To the caller
        # that is no different from a page it never got, so this answers nil and
        # leaves the explanation in the log.
        def nothing_left_to_book(page)
          puts "  API error: #{page["message"]} (nextDate: #{page["nextDate"]})"
          nil
        end
      end
    end
  end
end
