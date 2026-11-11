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
#   cineyelmo.com — where yelmocines.es now redirects: does the new site answer
#   this runner, and what does it fetch its programme from?
#
#   lacartelera.com — a candidate third provider for both venues: does it
#   answer this runner, and are its sessions in the page or behind an API?
#
# A known-good SensaCine request runs last as the control: if that fails too,
# the runner is the problem and nothing above it means anything.
#
# Run it through the "Capture API fixtures" workflow with provider=access.
# Read-only, and it needs no secrets.

require "bundler/setup"
require "json"
require "uri"
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

# Http::Client hands bodies back as binary; a UTF-8 pattern cannot match one.
def utf8(body) = body.to_s.dup.force_encoding(Encoding::UTF_8).scrub

def report(label, response)
  puts "\n===== BEGIN #{label} ====="
  puts "status: #{response.code}"
  response.each_header { |name, value| puts "  #{name}: #{value}" if name.match?(TELLING_HEADERS) }
  body = response.body.to_s
  puts "body: #{body.bytesize} bytes"
  puts cloudflare_verdict(body) || body.byteslice(0, BODY_SAMPLE).to_s.scrub
  puts "===== END #{label} ====="
  response
end

# A Cloudflare block page spends its first kilobytes on boilerplate; the reason
# for the block and the Ray ID come after. This is the part worth reading: a
# rule the site set for itself reads differently from anything upstream of it.
def cloudflare_verdict(body)
  return nil unless body[%r{<title>(.*?)</title>}im, 1].to_s.include?("Cloudflare")

  details = body[/<div id="cf-error-details".*/m].to_s.gsub(/<script.*?<\/script>/m, "")
  text    = details.gsub(/<[^>]+>/, " ").gsub(/&[a-z#0-9]+;/i, " ").squeeze(" \n").strip

  "Cloudflare says:\n#{text.lines.map(&:strip).reject(&:empty?).join("\n")}"
end

def html_client(extra = {}) = VoCinema::Http::Client.new(headers: HTML_HEADERS.merge(extra))

# A page as a browser would end up on it. Http::Client does not follow
# redirects, and both SensaCine and the Ocine site have moved their pages.
def browse(url, hops: 3)
  response = html_client.get(url)
  return response unless hops.positive? && response.code.start_with?("3") && response["location"]

  browse(URI.join(url, response["location"]).to_s, hops: hops - 1)
end

# The cookies a page hands out, as a Cookie header would send them back.
def cookies_from(response)
  Array(response.get_fields("set-cookie")).map { |cookie| cookie.split(";", 2).first }.join("; ")
end

# Where a page says its data comes from: scripts it loads, URL-looking strings
# that smell of an endpoint, and any inline JSON blob a modern front end ships.
def endpoints_in(label, html)
  html = utf8(html)
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
                   browse("#{SENSACINE::DOMAIN}/cines/cine/#{FRESNOS.sensacine_id}/"))
  title = theatre.first.body.to_s[%r{<title>(.*?)</title>}im, 1]
  puts "page title: #{title.to_s.strip.inspect}"
end

# ---------------------------------------------------------------------------
section "Los Fresnos 2/3 — SensaCine's theatres near Gijón, in case the id moved" do
  ocimax_page = browse("#{SENSACINE::DOMAIN}/cines/cine/#{OCIMAX.sensacine_id}/")
  puts "Ocimax theatre page: HTTP #{ocimax_page.code}"
  links  = (ocimax_page.body.to_s + theatre.first&.body.to_s).scan(%r{href=["']((?:https://www\.sensacine\.com)?/cines/[^"'#?]+)}i)
                                                                 .flatten.map { |link| link.sub(SENSACINE::DOMAIN, "") }.uniq
  puts "/cines/ links on the theatre pages:"
  links.first(40).each { |link| puts "  #{link}" }
  cities = links.grep(/ciudad|ciudades|\d{4,}/i).grep_v(%r{/cine/})
  puts "city pages to read: #{cities.inspect}"
  cities.first(2).each do |path|
    city = browse("#{SENSACINE::DOMAIN}#{path}")
    puts "\n#{path}: HTTP #{city.code}"
    city.body.to_s.scan(%r{href=["'][^"']*/cines/cine/?-?([A-Z0-9]+)/?["'][^>]*>\s*([^<]{2,120})}i)
        .uniq.each { |id, name| puts "  #{id}  #{name.strip}" }
  end
end

# ---------------------------------------------------------------------------
section "Los Fresnos 3/3 — the cinema's own site" do
  fresnos_site = report("ocine los fresnos home", browse(FRESNOS.url))
  endpoints_in("ocine los fresnos home", fresnos_site.body.to_s) if fresnos_site.code == "200"
end

# ---------------------------------------------------------------------------
# lacartelera.com, a candidate third provider: whether this runner may read it
# at all, and if so where its sessions live and how it labels a print's version.

LACARTELERA        = "https://www.lacartelera.com"
LACARTELERA_OCIMAX = "#{LACARTELERA}/es/cine/ocimax-gijon-asturias/".freeze
VERSION_LABELS     = { "VOSE" => /VOSE/, "V.O." => /V\.O\./, "VO" => /\bVO\b/, "Subtitulad" => /subtitulad/i,
                       "Doblad" => /doblad/i, "Castellano" => /castellano/i, "Español" => /espa[ñn]ol/i }.freeze

def text_of(html) = utf8(html).gsub(%r{<(script|style)\b.*?</\1>}im, " ").gsub(/<[^>]+>/, " ").gsub(/&[a-z#0-9]+;/i, " ").squeeze(" \n")

# What a page says about its sessions, without knowing its markup yet.
def sessions_in(label, html)
  puts "\n===== BEGIN #{label}: sessions ====="
  html = utf8(html)
  text = text_of(html)
  VERSION_LABELS.each do |name, pattern|
    hits = text.to_enum(:scan, pattern).map { Regexp.last_match.begin(0) }
    puts "label #{name}: #{hits.size}"
    hits.first(3).each { |at| puts "    …#{text[[at - 60, 0].max, 140].strip}…" }
  end
  times = text.scan(/\b(?:[01]\d|2[0-3])[:.][0-5]\d\b/)
  puts "clock times in the text: #{times.size}, e.g. #{times.uniq.first(12).inspect}"
  html.scan(%r{<script[^>]+application/ld\+json[^>]*>(.*?)</script>}im).flatten.each_with_index do |json, index|
    puts "ld+json #{index}: #{json.strip.byteslice(0, BODY_SAMPLE).scrub}"
  end
  puts "data-* attribute names: #{html.scan(/\sdata-([a-z0-9_-]+)=/i).flatten.tally.sort_by { -_2 }.first(25).inspect}"
  puts "===== END #{label}: sessions ====="
end

def links_in(html, pattern, base: LACARTELERA)
  utf8(html).scan(/href=["']([^"'#]+)["']/i).flatten.grep(pattern).map { |link| URI.join(base, link).to_s rescue link }.uniq
end

# ---------------------------------------------------------------------------
# cineyelmo.com: on 11 November every www.yelmocines.es URL answered 301 to
# https://cineyelmo.com/es, from an AWS load balancer rather than Cloudflare.
# Yelmo has moved. Does the new site answer this runner, and where does it get
# its programme from?

CINEYELMO     = "https://cineyelmo.com"
OCIMAX_LINK   = /ocimax|gij[oó]n|asturias/i
SITE_LINK     = /cine|cartelera|pelicul|horario|sesion|session|showtime|movie|film/i
# Strings in a script bundle that look like an API it calls.
BUNDLE_STRING = %r{["'`]((?:https?://[^"'`\s]{4,200})|(?:/[\w\-./${}]*(?:api|graphql|showtime|session|sesion|cartelera|cinema|cine|movie|pelicula|schedule|horario)[\w\-./${}?=&]*))["'`]}i

cineyelmo = {}

def same_site_scripts(html, base) = utf8(html).scan(/<script[^>]+src=["']([^"']+)["']/i).flatten
                                               .map { |src| URI.join(base, src).to_s rescue nil }.compact
                                               .select { |src| src.include?("cineyelmo") }.uniq

section "cineyelmo 1/4 — the new home page, from the runner" do
  home = report("cineyelmo home", browse("#{CINEYELMO}/es"))
  cineyelmo[:home] = home
  next unless home.code == "200"

  endpoints_in("cineyelmo home", home.body)
  puts "\nlinks that name Ocimax, Gijón or Asturias:"
  links_in(home.body, OCIMAX_LINK, base: CINEYELMO).first(30).each { |link| puts "  #{link}" }
  puts "links that look like programme pages:"
  links_in(home.body, SITE_LINK, base: CINEYELMO).first(40).each { |link| puts "  #{link}" }
end

section "cineyelmo 2/4 — robots.txt and the sitemap, for the URL patterns" do
  robots = report("cineyelmo robots", browse("#{CINEYELMO}/robots.txt"))
  sitemaps = utf8(robots.body).scan(/^sitemap:\s*(\S+)/i).flatten
  sitemaps = ["#{CINEYELMO}/sitemap.xml"] if sitemaps.empty?
  sitemaps.first(2).each do |url|
    sitemap = browse(url)
    locs = utf8(sitemap.body).scan(%r{<loc>\s*([^<]+?)\s*</loc>}i).flatten
    puts "\n#{url}: HTTP #{sitemap.code}, #{locs.size} <loc> entries"
    puts "  of which name Ocimax/Gijón/Asturias:"
    locs.grep(OCIMAX_LINK).first(20).each { |loc| puts "    #{loc}" }
    puts "  a sample of the rest:"
    locs.grep_v(OCIMAX_LINK).first(25).each { |loc| puts "    #{loc}" }
  end
end

section "cineyelmo 3/4 — the Ocimax page" do
  found   = links_in(cineyelmo[:home]&.body.to_s, OCIMAX_LINK, base: CINEYELMO)
  guesses = %w[/es/cines/ocimax-gijon /es/cine/ocimax-gijon /es/cartelera/asturias/ocimax-gijon
               /es/cines/asturias/ocimax-gijon].map { |path| "#{CINEYELMO}#{path}" }
  (found.first(3) + guesses).uniq.each do |url|
    page = report("cineyelmo #{URI(url).path}", browse(url))
    next unless page.code == "200"

    cineyelmo[:ocimax] ||= page
    endpoints_in("cineyelmo #{URI(url).path}", page.body)
    sessions_in("cineyelmo #{URI(url).path}", page.body)
    break
  end
  puts "\nNo Ocimax page answered 200." unless cineyelmo[:ocimax]
end

section "cineyelmo 4/4 — what the script bundles call, and the old endpoint on the new domain" do
  pages   = [cineyelmo[:home], cineyelmo[:ocimax]].compact.select { |page| page.code == "200" }
  scripts = pages.flat_map { |page| same_site_scripts(page.body, CINEYELMO) }.uniq
  puts "same-site scripts (#{scripts.size}):"
  scripts.each { |src| puts "  #{src}" }
  scripts.first(6).each do |src|
    bundle  = html_client.get(src)
    strings = utf8(bundle.body).scan(BUNDLE_STRING).flatten.uniq
    puts "\n===== BEGIN cineyelmo bundle #{URI(src).path}: HTTP #{bundle.code}, #{bundle.body.to_s.bytesize} bytes ====="
    strings.first(80).each { |string| puts "  #{string}" }
    puts "===== END cineyelmo bundle #{URI(src).path} ====="
  end

  headers = YELMO::HEADERS.merge("Referer" => "#{CINEYELMO}/es", "Origin" => CINEYELMO)
  report("cineyelmo GetNowPlaying",
         VoCinema::Http::Client.new(headers: headers)
                               .post("#{CINEYELMO}/now-playing.aspx/GetNowPlaying",
                                     JSON.generate({ cityKey: OCIMAX.yelmo_id.split("/").first })))
end

lacartelera = []

section "lacartelera 1/2 — the Ocimax page, from the runner" do
  page = report("lacartelera ocimax", browse(LACARTELERA_OCIMAX))
  lacartelera << page
  next unless page.code == "200"

  html = utf8(page.body)
  puts "\n===== BEGIN lacartelera ocimax: whole page, styles dropped ====="
  puts html.gsub(%r{<style\b.*?</style>}im, "<style>…</style>")
  puts "===== END lacartelera ocimax: whole page, styles dropped ====="
  endpoints_in("lacartelera ocimax", html)
  sessions_in("lacartelera ocimax", html)
  puts "\n/es/cine/ links:"
  links_in(html, %r{/es/cine/}).first(40).each { |link| puts "  #{link}" }
  puts "links that look like other days:"
  links_in(html, /fecha|dia=|date|\d{4}-\d{2}-\d{2}|manana|ma%C3%B1ana/i).first(20).each { |link| puts "  #{link}" }
end

section "lacartelera 2/2 — Los Fresnos" do
  fresnos = links_in(lacartelera.first&.body.to_s, /fresnos/i).first
  if fresnos
    page = report("lacartelera los fresnos", browse(fresnos))
    sessions_in("lacartelera los fresnos", page.body.to_s) if page.code == "200"
  else
    puts "The Ocimax page links no Los Fresnos page."
  end
end

# ---------------------------------------------------------------------------
section "Control — a SensaCine request known to work" do
  control = VoCinema::Http::Client.new(headers: SENSACINE::HEADERS)
                                  .get("#{SENSACINE::DOMAIN}/_/showtimes/theater-#{OCIMAX.sensacine_id}/d-#{VoCinema::Clock.today}/")
  parsed  = (JSON.parse(control.body) rescue {})
  puts "HTTP #{control.code}, error: #{parsed["error"].inspect}, results: #{parsed["results"].to_a.size}"
end
