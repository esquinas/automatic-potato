# frozen_string_literal: true

require "net/http"
require "uri"

module VoCinema
  module Http
    # The only code in the service that touches the network.
    #
    # Both cinema listings are scraped from endpoints meant for a browser, so a
    # request is followed by a pause rather than firing the next one the instant
    # it comes back, and a failure is given exactly one more chance behind a
    # much longer pause. Everything above this class builds URLs and reads JSON;
    # nothing above it knows what a socket is.
    class Client
      READ_TIMEOUT  = 10
      PACING        = (1.5..2.5)
      RETRY_BACKOFF = (15.0..25.0)

      # Both providers serve these endpoints to their own web pages and answer
      # 403 to anything that does not look like one, so every request to them
      # says it is a browser reading a Spanish cinema listing. Declared once
      # here; each caller adds what its own endpoint additionally wants.
      BROWSER = {
        "User-Agent"      => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " \
                             "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Accept-Language" => "es-ES,es;q=0.9"
      }.freeze

      def initialize(headers: {})
        @headers = headers
      end

      def get(url)
        deliver("GET", url) { Net::HTTP::Get.new(URI(url), @headers) }
      end

      def post(url, body)
        deliver("POST", url) do
          Net::HTTP::Post.new(URI(url), @headers).tap { |request| request.body = body }
        end
      end

      private

      def deliver(verb, url, &build_request)
        puts "#{verb} #{url}"
        response = with_one_retry(url, &build_request)
        puts "HTTP #{response.code}"
        response
      end

      # The block is called again rather than the request reused: a Net::HTTP
      # request that has been on the wire once is not safe to send a second time.
      def with_one_retry(url, &build_request)
        response = attempt(build_request.call, PACING)
        return response if response.code == "200"

        puts "Retrying #{url}"
        attempt(build_request.call, RETRY_BACKOFF, " (retry backoff)")
      end

      def attempt(request, pause_range, note = "")
        response = dispatch(request)
        pause(pause_range, note)
        response
      end

      def dispatch(request)
        uri = request.uri
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: READ_TIMEOUT) do |connection|
          connection.request(request)
        end
      end

      def pause(range, note)
        jitter = rand(range)
        puts "Jitter #{format("%.2f", jitter)}s#{note}"
        sleep(jitter)
      end
    end
  end
end
