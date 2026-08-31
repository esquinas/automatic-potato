# frozen_string_literal: true

require "json"

module VoCinema
  module Showtimes
    # The authoritative source for what is subtitled at Yelmo Ocimax Gijón.
    #
    # SensaCine files Yelmo's VOSE prints under "dubbed"; Yelmo's own listings
    # tag them properly. This class deals only in requests — one per city,
    # cached, because a single answer covers every cinema in it for the whole
    # week. Reading that answer is Listing's job.
    class Yelmo
      DOMAIN = "https://www.yelmocines.es"

      # GetNowPlaying is the endpoint behind yelmocines.es/cartelera and only
      # answers what looks like that page's own XHR.
      HEADERS = Http::Client::BROWSER.merge(
        "Content-Type"     => "application/json; charset=UTF-8",
        "X-Requested-With" => "XMLHttpRequest",
        "Accept"           => "application/json, text/javascript, */*; q=0.01",
        "Referer"          => "#{DOMAIN}/cartelera"
      ).freeze

      def initialize(http: Http::Client.new(headers: HEADERS))
        @http  = http
        @cache = {}
      end

      # How the run log names this provider when reporting what the providers
      # disagreed about.
      def name = "Yelmo"

      # Yelmo runs a handful of cinemas; it has nothing to say about the rest.
      def sessions_for(cinema, date)
        theater_id = cinema.yelmo_id
        return [] unless theater_id

        days_at(theater_id).fetch(date, [])
      end

      private

      def days_at(theater_id)
        @cache[theater_id] ||= Listing.new(find_cinema(theater_id)).by_date
      end

      # A yelmo_id is "city-key/cinema-key": Yelmo is asked about the city and
      # the cinema is picked out of the answer.
      def find_cinema(theater_id)
        city_key, cinema_key = theater_id.split("/", 2)
        in_the_city          = cinemas_in(city_key)

        in_the_city.find { |cinema| cinema["Key"] == cinema_key } ||
          report_missing(cinema_key, in_the_city)
      end

      # Always answers nil — a cinema that is not in the payload is not a
      # cinema. Silent when the request itself failed, since that is already
      # logged and an empty city says nothing about this venue.
      def report_missing(cinema_key, in_the_city)
        return nil if in_the_city.empty?

        puts "  Yelmo: cinema #{cinema_key.inspect} not found " \
             "(available: #{in_the_city.map { |cinema| cinema["Key"] }.inspect})"
        nil
      end

      def cinemas_in(city_key)
        response = @http.post("#{DOMAIN}/now-playing.aspx/GetNowPlaying", JSON.generate({ cityKey: city_key }))
        return [] unless response.code == "200"

        JSON.parse(response.body).dig("d", "Cinemas") || []
      end
    end
  end
end
