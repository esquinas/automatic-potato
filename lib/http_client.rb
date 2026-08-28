# frozen_string_literal: true

require "net/http"
require "uri"

module HttpClient
  def http_get(url, headers = {}, retried: false)
    uri  = URI(url)
    req  = Net::HTTP::Get.new(uri, headers)
    resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 10) { |h| h.request(req) }
    jitter_range = retried ? (15.0..25.0) : (1.5..2.5)
    jitter = rand(jitter_range)
    puts "Jitter #{format('%.2f', jitter)}s#{' (retry backoff)' if retried}"
    sleep(jitter)
    return resp if resp.code == "200" || retried

    puts "Retrying #{url}"
    http_get(url, headers, retried: true)
  end

  def http_post(url, body, headers = {}, retried: false)
    uri      = URI(url)
    req      = Net::HTTP::Post.new(uri, headers)
    req.body = body
    resp     = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 10) { |h| h.request(req) }
    jitter_range = retried ? (15.0..25.0) : (1.5..2.5)
    jitter = rand(jitter_range)
    puts "Jitter #{format('%.2f', jitter)}s#{' (retry backoff)' if retried}"
    sleep(jitter)
    return resp if resp.code == "200" || retried

    puts "Retrying #{url}"
    http_post(url, body, headers, retried: true)
  end
end
