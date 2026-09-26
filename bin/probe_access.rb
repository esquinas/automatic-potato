#!/usr/bin/env ruby
# frozen_string_literal: true

# Asks why a provider stopped answering, from the network the service runs on.
#
# Written after the 25 September digest (see "What broke on 25 September" in
# CLAUDE.md): Yelmo's GetNowPlaying had answered 403 since 23 September, and
# SensaCine had answered no.showtime.error for Ocine Premium Los Fresnos every
# day since at least 18 September. Each has more than one explanation, and each
# explanation wants a different fix, so this prints what tells them apart:
#
#   Yelmo — is the whole domain refusing this runner (a WAF or bot shield, which
#   shows in the headers), has the endpoint gone with the site's redesign (the
#   pages answer, the endpoint does not, and the new page names what it fetches
#   instead), or does it now want the session a browser picks up first?
#
#   Los Fresnos — does SensaCine still list the venue, under this id or another,
#   and what does the cinema's own site fetch its programme from?
#
# A known-good SensaCine request runs last as the control: if that fails too,
# the runner is the problem and nothing above it means anything.
#
# Run it through the "Capture API fixtures" workflow with provider=access.
# Read-only, and it needs no secrets.

require "bundler/setup"
require "json"
require_relative "../lib/vo_cinema"

YELMO     = VoCinema::Showtimes::Yelmo
SENSACINE = VoCinema::Showtimes::Sensacine
BROWSER   = VoCinema::Http::Client::BROWSER
CINEMAS   = VoCinema::Cinema.all
OCIMAX    = CINEMAS.find(&:yelmo_id)
FRESNOS   = CINEMAS.find { |cinema| cinema.name.include?("Fresnos") }

BODY_SAMPLE = 1500
# Headers worth reading when a request is refused: who answered, whether a
# shield did, and whether a session is being handed out.
TELLING_HEADERS = /\A(server|content-type|content-length|location|set-cookie|cf-|x-|akamai|via|retry-after)/i
# Strings in a page that look like where it fetches its data from.
ENDPOINT_HINTS = /api|\.aspx\/|graphql|\.json|showtime|sesion|session|cartelera|programa|horario/i

HTML_HEADERS = BROWSER.merge("Accept" => "text/html,application/xhtml+xml,*/*;q=0.8").freeze

# Each step reports on its own: a refused connection is an answer too, and it
# must not cost the steps after it.
def section(title)
  puts("\n\n########## #{title} ##########\n")
  yield
rescue StandardError => e
  puts "  #{e.class}: #{e.message}"
end

def report(label, response)
  puts "\n===== BEGIN #{label} ====="
  puts "status: #{response.code}"
  response.each_header { |name, value| puts "  #{name}: #{value}" if name.match?(TELLING_HEADERS) }
  body = response.body.to_s
  puts "body: #{body.bytesize} bytes"
  puts body.byteslice(0, BODY_SAMPLE).to_s.scrub
  puts "===== END #{label} ====="
  response
end

def html_client(extra = {}) = VoCinema::Http::Client.new(headers: HTML_HEADERS.merge(extra))

# The cookies a page hands out, as a Cookie header would send them back.
def cookies_from(response)
  Array(response.get_fields("set-cookie")).map { |cookie| cookie.split(";", 2).first }.join("; ")
end

# Where a page says its data comes from: scripts it loads, URL-looking strings
# that smell of an endpoint, and any inline JSON blob a modern front end ships.
def endpoints_in(label, html)
  puts "\n===== BEGIN #{label}: what the page fetches ====="
  scripts = html.scan(/<script[^>]+src=["']([^"']+)["']/i).flatten.uniq
  puts "scripts (#{scripts.size}):"
  scripts.each { |src| puts "  #{src}" }

  urls = html.scan(%r{["'`]((?:https?:)?/[^"'`\s<>]{3,200})["'`]}).flatten.uniq.grep(ENDPOINT_HINTS)
  puts "endpoint-looking strings (#{urls.size}):"
  urls.first(80).each { |url| puts "  #{url}" }

  %w[__NEXT_DATA__ __NUXT__ __INITIAL_STATE__ __APOLLO_STATE__ window.__].each do |marker|
    puts "inline state: #{marker} present" if html.include?(marker)
  end
  puts "===== END #{label}: what the page fetches ====="
end

YELMO_PAGES = {
  "yelmo home"      => "#{YELMO::DOMAIN}/",
  "yelmo cartelera" => "#{YELMO::DOMAIN}/cartelera",
  "yelmo ocimax"    => "#{YELMO::DOMAIN}/cartelera/#{OCIMAX.yelmo_id}",
  "yelmo robots"    => "#{YELMO::DOMAIN}/robots.txt"
}.freeze

# What one step learns and a later one reads. Filled in place, because a step
# is a block and anything it assigns would stay inside it.
yelmo_pages = {}
theatre     = []

def now_playing(http) = http.post("#{YELMO::DOMAIN}/now-playing.aspx/GetNowPlaying", JSON.generate({ cityKey: OCIMAX.yelmo_id.split("/").first }))

# ---------------------------------------------------------------------------
section "Yelmo 1/4 — GetNowPlaying, asked exactly as production asks" do
  report("yelmo GetNowPlaying", now_playing(VoCinema::Http::Client.new(headers: YELMO::HEADERS)))
end

# ---------------------------------------------------------------------------
section "Yelmo 2/4 — is it the endpoint or the whole domain?" do
  YELMO_PAGES.each { |label, url| yelmo_pages[label] = report(label, html_client.get(url)) }
end

# ---------------------------------------------------------------------------
section "Yelmo 3/4 — what the redesigned pages fetch" do
  yelmo_pages.each do |label, response|
    endpoints_in(label, response.body.to_s) if response.code == "200" && !label.include?("robots")
  end
end

# ---------------------------------------------------------------------------
section "Yelmo 4/4 — GetNowPlaying again, carrying the session the pages handed out" do
  cookies = yelmo_pages.values.map { |response| cookies_from(response) }.reject(&:empty?).join("; ")
  if cookies.empty?
    puts "No page set a cookie, so there is no session to carry."
  else
    puts "Cookie names: #{cookies.split("; ").map { |pair| pair.split("=", 2).first }.inspect}"
    headers = YELMO::HEADERS.merge("Cookie" => cookies, "Referer" => YELMO_PAGES["yelmo ocimax"],
                                   "Origin" => YELMO::DOMAIN)
    report("yelmo GetNowPlaying with session", now_playing(VoCinema::Http::Client.new(headers: headers)))
  end
end

# ---------------------------------------------------------------------------
section "Los Fresnos 1/3 — does SensaCine still list #{FRESNOS.sensacine_id}?" do
  theatre << report("sensacine theatre #{FRESNOS.sensacine_id}",
                   html_client.get("#{SENSACINE::DOMAIN}/cines/cine-#{FRESNOS.sensacine_id}/"))
  title = theatre.first.body.to_s[%r{<title>(.*?)</title>}im, 1]
  puts "page title: #{title.to_s.strip.inspect}"
end

# ---------------------------------------------------------------------------
section "Los Fresnos 2/3 — SensaCine's theatres near Gijón, in case the id moved" do
  ocimax_page = html_client.get("#{SENSACINE::DOMAIN}/cines/cine-#{OCIMAX.sensacine_id}/")
  puts "Ocimax theatre page: HTTP #{ocimax_page.code}"
  cities = (ocimax_page.body.to_s + theatre.first&.body.to_s).scan(%r{/cines/[a-z-]*ciudad-?\d+/?}i).uniq
  puts "city pages linked: #{cities.inspect}"
  cities.first(2).each do |path|
    city = html_client.get("#{SENSACINE::DOMAIN}#{path}")
    puts "\n#{path}: HTTP #{city.code}"
    city.body.to_s.scan(%r{href=["'][^"']*/cines/cine-([A-Z0-9]+)/?["'][^>]*>\s*([^<]{2,120})}i)
        .uniq.each { |id, name| puts "  #{id}  #{name.strip}" }
  end
end

# ---------------------------------------------------------------------------
section "Los Fresnos 3/3 — the cinema's own site" do
  fresnos_site = report("ocine los fresnos home", html_client.get(FRESNOS.url))
  endpoints_in("ocine los fresnos home", fresnos_site.body.to_s) if fresnos_site.code == "200"
end

# ---------------------------------------------------------------------------
section "Control — a SensaCine request known to work" do
  control = VoCinema::Http::Client.new(headers: SENSACINE::HEADERS)
                                  .get("#{SENSACINE::DOMAIN}/_/showtimes/theater-#{OCIMAX.sensacine_id}/d-#{VoCinema::Clock.today}/")
  parsed  = (JSON.parse(control.body) rescue {})
  puts "HTTP #{control.code}, error: #{parsed["error"].inspect}, results: #{parsed["results"].to_a.size}"
end
