# frozen_string_literal: true

require "date"

# Turns a week's listings into the message a subscriber reads.
#
# Pure: it asks nobody anything and changes nothing. Give it the same listings
# twice and it produces the same text, which is what makes the digest cheap to
# test and cheap to reason about.
class DigestRenderer
  TELEGRAM_MAX_MSG_CHARS = 3800

  def initialize(today:, week_days:)
    @today     = today
    @week_days = week_days
  end

  def render(listings, nothing_left_at)
    lines = listings.flat_map { |listing| [*cinema_section(listing), ""] }
    lines.concat(closing_notes(nothing_left_at))

    within_telegram_limit(lines.join("\n").strip)
  end

  private

  def cinema_section(listing)
    [cinema_heading(listing), *listing.films.flat_map { |film| film_entry(listing, film) }]
  end

  def cinema_heading(listing)
    label = "#{listing.name} — #{@today} → #{week_end}"
    listing.url ? "<b><a href=\"#{listing.url}\">#{label}</a></b>" : "<b>#{label}</b>"
  end

  def week_end = (@today + @week_days - 1).to_s

  def film_entry(listing, film)
    ["", title_line(film, listing.rating_for(film)), showtimes_block(listing.sessions_for(film))]
  end

  def title_line(film, rating)
    parts = ["<b>#{film.localized_title}</b>"]
    parts << "<i>(#{film.title})</i>" if renamed_for_spain?(film)
    parts << rating
    parts.join(" ").strip
  end

  # Printing both titles is only worth the width when they actually differ;
  # TMDB and the cinemas often disagree on nothing but capitals.
  def renamed_for_spain?(film)
    original = film.title
    original && original.downcase != film.localized_title.downcase
  end

  def showtimes_block(sessions)
    by_date = sessions.group_by(&:date)
                      .transform_values { |group| group.map(&:starts_at).sort.uniq }
                      .sort.to_h
    width   = by_date.values.flatten.map(&:length).max
    body    = by_date.length == @week_days ? all_week(by_date, width) : day_by_day(by_date, width)

    "<pre>#{body}</pre>"
  end

  # A film showing every single day would otherwise take seven lines and crowd
  # out the one-off screenings that are the point of the digest.
  def all_week(by_date, width)
    "• All week: #{by_date.keys.min} → #{by_date.keys.max}\n  " \
      "#{aligned(by_date.values.flatten.sort.uniq, width)}"
  end

  def day_by_day(by_date, width)
    by_date.map { |date, times| "• #{weekday(date)} → #{aligned(times, width)}" }.join("\n")
  end

  def aligned(times, width)
    times.map { |time| time.rjust(width) }.join(", ")
  end

  def weekday(date) = Date.parse(date).strftime("%a")

  # Both providers list only screenings you could still buy a ticket for, so a
  # day drains as its programme runs and a venue that came back empty has not
  # necessarily programmed nothing — its screenings may already have been
  # shown. Neither line below claims otherwise, and neither should anything
  # that replaces them: see "An empty day means expired, not absent" in
  # CLAUDE.md.
  def closing_notes(nothing_left_at)
    notes = []
    notes += ["Nothing left to catch this week at: #{nothing_left_at.join(", ")}", ""] unless nothing_left_at.empty?
    notes << "Today lists only what is still to come; earlier screenings have already been shown."
    notes
  end

  # Telegram rejects anything longer outright, which would cost the whole
  # digest rather than its tail.
  def within_telegram_limit(message)
    return message if message.length <= TELEGRAM_MAX_MSG_CHARS

    "#{message[0, TELEGRAM_MAX_MSG_CHARS]}\n... (truncated)"
  end
end
