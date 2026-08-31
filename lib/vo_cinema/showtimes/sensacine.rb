# frozen_string_literal: true

module VoCinema
  module Showtimes
    # Fetches a theatre's day from SensaCine's internal JSON API.
    #
    # All this class settles is which URL a cinema and a date make, and which
    # venues it can speak for at all. How many pages that day took is Pages'
    # job; turning the entries into screenings is Day's.
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
        theater_id = cinema.sensacine_id
        return [] unless theater_id

        Day.new(Pages.new(@http, day_url(theater_id, date)).entries, date).sessions
      end

      private

      def day_url(theater_id, date) = "#{DOMAIN}/_/showtimes/theater-#{theater_id}/d-#{date}/"
    end
  end
end
