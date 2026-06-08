# frozen_string_literal: true

require "json"
require_relative "http_client"
require_relative "parsers/sensacine_session_parser"

class SensacineClient
  include HttpClient

  DOMAIN = "https://www.sensacine.com"

  def initialize(parser: Parsers::SensacineSessionParser.new)
    @parser = parser
  end

  HEADERS = {
    "User-Agent"      => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Accept"          => "application/json",
    "Accept-Language" => "es-ES,es;q=0.9",
    "Referer"         => "#{DOMAIN}/cines/cine/"
  }.freeze

  def fetch_theater_movie_sessions(date:, theater_id:)
    url = "#{DOMAIN}/_/showtimes/theater-#{theater_id}/d-#{date}/p-1/"

    puts "GET #{url}"
    resp = http_get(url, HEADERS)
    puts "HTTP #{resp.code}"
    return [] unless resp.code == "200"

    @parser.parse(JSON.parse(resp.body)["results"] || [], date)
  end
end
