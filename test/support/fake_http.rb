# frozen_string_literal: true

require "net/http"
require "uri"

# The only thing this suite fakes is the process boundary: the moment
# Net::HTTP would open a socket.
#
# Everything above that line runs for real — URL building, headers, the retry
# loop, JSON parsing, bucket classification, session mapping. That is what
# makes the suite survive refactoring: rename +http_get+, turn +HttpClient+
# into a base class, move pagination into its own object, and these tests
# still pass, because none of them names a method the project owns.
#
#   http = FakeHttp.new
#   http.answers "showtimes/theater-E0628/d-2026-08-28",
#                body: Fixtures.read("sensacine/ocimax_all_dubbed.json")
#
#   sessions = http.while_intercepting do
#     SensacineClient.new.fetch_theater_movie_sessions(date: "2026-08-28", theater_id: "E0628")
#   end
#
#   http.requests.first.url      # exactly what went on the wire
#   http.requests.first.headers  # ...and with which headers
class FakeHttp
  # One request as the code under test actually sent it.
  Request = Struct.new(:verb, :url, :headers, :body, keyword_init: true)

  # Raised instead of letting a test touch the real internet. The message
  # names the URL that was asked for and everything that was stubbed, which is
  # usually enough to see the typo without opening the test.
  class UnexpectedRequest < StandardError; end

  # Installed once for the whole run: nothing in this suite may open a real
  # socket. #while_intercepting swaps in canned answers for the duration of a
  # block; anything outside one gets an exception naming the host it reached
  # for, so a test that forgets to stub fails at once instead of quietly
  # talking to SensaCine from a CI runner.
  def self.block_real_connections
    Net::HTTP.define_singleton_method(:start) do |address = nil, *, **, &_block|
      raise UnexpectedRequest,
            "Something tried to reach #{address.inspect} for real. Wrap it in FakeHttp#while_intercepting."
    end
  end

  def initialize
    @answers  = []
    @requests = []
  end

  attr_reader :requests

  # Every request whose URL matches gets this same reply. A String matches as a
  # substring of the URL, a Regexp as a pattern.
  #
  #   http.answers "api.themoviedb.org/3/search/movie", body: search_results_json
  #   http.answers "theater-G02A3", status: "503"
  #
  # The first matcher that matches a URL wins, so where one matcher is a
  # substring of another — a paginated "…/d-2026-08-28/?page=2" inside a plain
  # "…/d-2026-08-28/" — register the specific one first.
  def answers(url_matcher, status: "200", body: "")
    answers_in_turn(url_matcher, [{ status: status, body: body }])
  end

  # Successive matching requests get successive replies; once the list runs
  # out the final reply repeats. This is how a flaky endpoint or a paginated
  # one is described:
  #
  #   http.answers_in_turn "theater-E0628", [
  #     { status: "503", body: "" },   # first attempt fails
  #     { status: "200", body: json }  # the retry succeeds
  #   ]
  def answers_in_turn(url_matcher, replies)
    @answers << { matcher: url_matcher, replies: replies.dup, served: 0 }
    self
  end

  # Runs the block with Net::HTTP disconnected from the network.
  def while_intercepting
    install
    yield
  ensure
    uninstall
  end

  def requests_to(url_matcher)
    requests.select { |request| matches?(url_matcher, request.url) }
  end

  # Stands in for the Net::HTTP connection object that Net::HTTP.start yields.
  # It answers the one message the connection is ever sent: #request.
  def request(net_http_request)
    url = net_http_request.uri.to_s
    @requests << Request.new(
      verb:    net_http_request.method,
      url:     url,
      headers: net_http_request.each_header.to_h,
      body:    net_http_request.body
    )
    reply_for(url)
  end

  private

  def reply_for(url)
    answer = @answers.find { |candidate| matches?(candidate[:matcher], url) }
    raise UnexpectedRequest, unexpected_message(url) unless answer

    reply = answer[:replies][answer[:served]] || answer[:replies].last
    answer[:served] += 1
    build_response(reply.fetch(:status, "200"), reply.fetch(:body, ""))
  end

  def unexpected_message(url)
    stubbed = @answers.map { |a| "  - #{a[:matcher].inspect}" }.join("\n")
    "Nothing stubbed for #{url}\nStubbed matchers:\n#{stubbed.empty? ? "  (none)" : stubbed}"
  end

  def matches?(matcher, url)
    matcher.is_a?(Regexp) ? url.match?(matcher) : url.include?(matcher)
  end

  # A genuine Net::HTTPResponse, not a lookalike, so code is free to ask it
  # anything a real response answers — #code, #body, is_a?(Net::HTTPSuccess).
  def build_response(status, body)
    klass    = Net::HTTPResponse::CODE_TO_OBJ.fetch(status)
    response = klass.new("1.1", status, klass.name.split("::").last)
    response.instance_variable_set(:@read, true)
    response.instance_variable_set(:@body, body)
    response
  end

  # Whatever Net::HTTP.start was before this fake took over is kept here, not
  # under a shared alias: two fakes nested inside one another would otherwise
  # save each other's stand-in and the outer unwind would leave the fake
  # installed, silently retiring the real-connection guard for the rest of the
  # run. Re-entering on the same fake still has nowhere to put the second
  # original, so that says so instead of quietly losing one.
  def install
    raise "This FakeHttp is already intercepting" if @start_before_faking

    connection = self
    @start_before_faking = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |*, **, &block| block.call(connection) }
  end

  def uninstall
    return unless @start_before_faking

    Net::HTTP.define_singleton_method(:start, @start_before_faking)
    @start_before_faking = nil
  end
end
