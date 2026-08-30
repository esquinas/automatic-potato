# frozen_string_literal: true

# Delivers the digest to the terminal, for developing without a Telegram token.
class StdoutMessenger
  def initialize(**) = nil

  def send_message(text)
    puts text
  end
end
