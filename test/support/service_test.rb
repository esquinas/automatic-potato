# frozen_string_literal: true

require "stringio"

# Base class for every test in the suite.
#
# The production classes narrate themselves to stdout — "GET https://…",
# "HTTP 200", "Sent 412 chars". That log is worth having in GitHub Actions and
# is pure noise in a test report, so each test runs with stdout captured and
# can read it back through #printed_output. Run with VERBOSE=1 to watch it.
#
# VERBOSE tees rather than stepping aside: it used to hand stdout straight to
# the terminal, which left #printed_output empty and failed every test that
# reads the log — so the documented way to watch a run was also the way to
# break the suite.
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
    $stdout = ENV["VERBOSE"] ? Tee.new(@captured_output, @stdout_before_test) : @captured_output
  end

  def after_teardown
    $stdout = @stdout_before_test
    super
  end

  def printed_output = @captured_output.string
end
