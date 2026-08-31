# frozen_string_literal: true

# Writes everything it is given to several places at once.
#
# ServiceTest captures stdout so tests can read back what the run logged, and
# VERBOSE=1 exists so a person can watch that log go by. Those two wants used
# to be exclusive: under VERBOSE nothing was captured, so every test asserting
# on #printed_output failed. Teeing satisfies both — the buffer still fills,
# and the terminal still shows it.
class Tee
  def initialize(*destinations)
    @destinations = destinations
  end

  # $stdout is written to through several different methods depending on
  # whether the caller reached for Kernel#puts, #print, #p or the stream
  # itself, so all of them have to go somewhere.
  def write(*chunks) = @destinations.map { |destination| destination.write(*chunks) }.first

  def puts(*lines) = broadcast { |destination| destination.puts(*lines) }

  def print(*parts) = broadcast { |destination| destination.print(*parts) }

  def <<(chunk) = broadcast { |destination| destination << chunk }

  def flush = broadcast(&:flush)

  # $stdout is expected to answer these; nothing here buffers, so both are
  # honest as written.
  def sync = true

  def sync=(setting)
    setting
  end

  private

  def broadcast(&sending)
    @destinations.each(&sending)
    self
  end
end
