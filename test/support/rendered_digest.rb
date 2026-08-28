# frozen_string_literal: true

# Reads a delivered Telegram digest the way a subscriber would.
#
# Tests ask this what the message *says* — which film, at which times, under
# which cinema — never how it is punctuated. That keeps them green when the
# bullet becomes a dash, the arrow becomes a colon, or <pre> is swapped for
# something else, and red when a screening actually goes missing.
class RenderedDigest
  def initialize(raw)
    @raw = raw.to_s
  end

  attr_reader :raw

  # The message as it reads in Telegram, with the markup taken off.
  def text
    @text ||= raw.gsub(/<[^>]+>/, "")
                 .gsub("&amp;", "&")
                 .gsub("&lt;", "<")
                 .gsub("&gt;", ">")
                 .gsub("&quot;", '"')
  end

  def mentions?(phrase) = text.include?(phrase)

  # Cinema headers and films are each set off by a blank line, so a block is
  # one cinema heading, or one film together with its showtimes.
  def blocks
    text.split(/\n{2,}/).map(&:strip).reject(&:empty?)
  end

  # The block introduced by the given title or cinema name. Refuses to guess:
  # the same film can play at two venues, and "Harry Potter y la Piedra
  # Filosofal" is a prefix of "…25 Aniversario". Narrow with #under first.
  def block_about(subject)
    matching = blocks.select { |block| block.lines.first.to_s.include?(subject) }

    raise "The digest says nothing about #{subject.inspect}. It says:\n\n#{text}" if matching.empty?

    if matching.length > 1
      raise "#{subject.inspect} matches #{matching.length} blocks — say which one you mean:\n\n" \
            "#{matching.map { |block| block.lines.first }.join}"
    end

    matching.first
  end

  # Just one cinema's part of the digest, so a film playing at two venues can
  # be asked about at one of them. Cinema headings are the only lines carrying
  # both ends of the week's date range, which is what marks the boundaries.
  #
  # The result is plain text, so it answers questions about wording but not
  # about links.
  def under(cinema_name)
    collecting = false
    lines = text.lines.select do |line|
      collecting = line.include?(cinema_name) if cinema_heading?(line)
      collecting
    end
    raise "No cinema called #{cinema_name.inspect} in the digest:\n\n#{text}" if lines.empty?

    RenderedDigest.new(lines.join)
  end

  def mentions_anywhere?(subject)
    blocks.any? { |block| block.include?(subject) }
  end

  # Every clock time listed under a film, in the order it is printed.
  def times_listed_for(film_title)
    block_about(film_title).scan(/\b\d{1,2}:\d{2}\b/)
  end

  # The URLs the message links to.
  def links = raw.scan(/href="([^"]*)"/).flatten

  private

  def cinema_heading?(line)
    line.scan(/\d{4}-\d{2}-\d{2}/).length >= 2
  end
end
