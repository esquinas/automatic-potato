# frozen_string_literal: true

require "date"

# Renders a WeeklyDigest as plain text. The rendering algorithm lives here;
# markup-specific formatters (e.g. HtmlFormatter) subclass and override only
# the markup primitives: bold, italic, link, preformatted.
class PlainTextFormatter
  def initialize(**) = nil

  def render(digest)
    sections = digest.programs.map { |program| cinema_section(program, digest) }
    sections << quiet_cinemas_note(digest.quiet_cinemas) unless digest.quiet_cinemas.empty?
    sections.join("\n\n")
  end

  private

  # -- markup primitives (overridden by markup-specific subclasses) ---------

  def bold(text)          = text
  def italic(text)        = text
  def link(text, _url)    = text
  def preformatted(text)  = text

  # -- rendering algorithm ---------------------------------------------------

  def cinema_section(program, digest)
    [cinema_header(program.cinema, digest), *program.listings.map { |listing| film_block(listing, digest) }].join("\n\n")
  end

  def cinema_header(cinema, digest)
    label = "#{cinema.name} — #{digest.from} → #{digest.to}"
    bold(cinema.url ? link(label, cinema.url) : label)
  end

  def film_block(listing, digest)
    [title_line(listing), preformatted(schedule_lines(listing, digest).join("\n"))].join("\n")
  end

  def title_line(listing)
    film  = listing.film
    parts = [bold(film.localized_title)]
    parts << italic("(#{film.title})") if film.translated?
    parts << listing.rating
    parts.join(" ").strip
  end

  def schedule_lines(listing, digest)
    by_date = listing.showtimes_by_date
    width   = by_date.values.flatten.map(&:length).max

    if by_date.size == digest.days
      times = by_date.values.flatten.sort.uniq
      ["• All week: #{by_date.keys.min} → #{by_date.keys.max}",
       "  #{aligned(times, width)}"]
    else
      by_date.map { |date, times| "• #{weekday(date)} → #{aligned(times, width)}" }
    end
  end

  def aligned(times, width)
    times.map { |time| time.rjust(width) }.join(", ")
  end

  def weekday(date_str)
    Date.parse(date_str).strftime("%a")
  end

  def quiet_cinemas_note(names)
    "The following venues had no VO sessions: #{names.join(", ")}"
  end
end
