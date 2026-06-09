# frozen_string_literal: true

require_relative "plain_text_formatter"

# Telegram-flavoured HTML: same rendering algorithm as PlainTextFormatter,
# only the markup primitives differ.
class HtmlFormatter < PlainTextFormatter
  private

  def bold(text)         = "<b>#{text}</b>"
  def italic(text)       = "<i>#{text}</i>"
  def link(text, url)    = "<a href=\"#{url}\">#{text}</a>"
  def preformatted(text) = "<pre>#{text}</pre>"
end
