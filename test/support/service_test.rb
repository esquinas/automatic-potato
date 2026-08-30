# frozen_string_literal: true

require "stringio"

# Base class for every test in the suite.
#
# The production classes narrate themselves to stdout — "GET https://…",
# "HTTP 200", "Sent 412 chars". That log is worth having in GitHub Actions and
# is pure noise in a test report, so each test runs with stdout captured and
# can read it back through #printed_output. Run with VERBOSE=1 to watch it.
#
# This hooks before_setup/after_teardown rather than setup/teardown so that
# subclasses can define setup without having to remember to call super.
class ServiceTest < Minitest::Test
  # Tests name the domain the way the code does — Film, Showtimes::Sensacine —
  # rather than repeating the top-level namespace on every line, exactly as
  # application code inside VoCinema does.
  include VoCinema

  def before_setup
    super
    RecordedSleeps.reset
    @captured_output    = StringIO.new
    @stdout_before_test = $stdout
    $stdout = @captured_output unless ENV["VERBOSE"]
  end

  def after_teardown
    $stdout = @stdout_before_test
    super
  end

  def printed_output = @captured_output.string
end
