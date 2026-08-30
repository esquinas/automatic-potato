# frozen_string_literal: true

require "net/http"
require "uri"

# The manners every client in the service shares.
#
# Both cinema listings are scraped from endpoints meant for a browser, so a
# request is followed by a pause rather than firing the next one the instant it
# comes back, and a failure is given exactly one more chance behind a much
# longer pause. GET and POST differ only in the request they build; everything
# after that was written out twice and now lives here once.
module HttpClient
  READ_TIMEOUT  = 10
  PACING        = (1.5..2.5)
  RETRY_BACKOFF = (15.0..25.0)

  def http_get(url, headers = {})
    with_one_retry(url) { Net::HTTP::Get.new(URI(url), headers) }
  end

  def http_post(url, body, headers = {})
    with_one_retry(url) do
      Net::HTTP::Post.new(URI(url), headers).tap { |request| request.body = body }
    end
  end

  private

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
