# frozen_string_literal: true

require "date"

module VoCinema
  module Digest
    # Turns a week's listings into the message a subscriber reads.
    #
    # Pure: it asks nobody anything and changes nothing. Give it the same listings
    # twice and it produces the same text, which is what makes the digest cheap to
    # test and cheap to reason about.
    class Renderer
      def initialize(today:, week_days:)
        @today     = today
        @week_days = week_days
      end

      def render(listings, nothing_left_at)
        lines = listings.flat_map { |listing| [*cinema_section(listing), ""] }
        lines.concat(closing_notes(nothing_left_at))

        lines.join("\n").strip
      end

      private

      def cinema_section(listing)
        [cinema_heading(listing), *listing.films.flat_map { |film| film_entry(listing, film) }]
      end

      def cinema_heading(listing)
        label = "#{listing.name} — #{@today} → #{week_end}"
        url   = listing.url
        url ? "<b><a href=\"#{url}\">#{label}</a></b>" : "<b>#{label}</b>"
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

      def showtimes_block(sessions) = "<pre>#{Timetable.new(sessions, week_days: @week_days)}</pre>"

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
    end
  end
end
