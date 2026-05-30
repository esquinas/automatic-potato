# frozen_string_literal: true

class StdoutMessenger
  def initialize(**) = nil

  def send_message(text)
    puts text
  end
end
