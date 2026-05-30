# frozen_string_literal: true

require "net/http"
require "uri"

module HttpClient
  def http_get(url, headers = {}, retried: false)
    sleep(1.5 + rand)
    uri  = URI(url)
    req  = Net::HTTP::Get.new(uri, headers)
    resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 10) { |h| h.request(req) }
    return resp if resp.code == "200" || retried

    puts "Retrying #{url}"
    http_get(url, headers, retried: true)
  end
end
