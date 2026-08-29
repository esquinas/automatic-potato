# frozen_string_literal: true

# The clients pause between requests so the providers are not hammered: a
# couple of seconds normally, fifteen to twenty-five before a retry. That is
# correct in production and intolerable in a test run, where a single
# end-to-end example makes sixty requests.
#
# So the suite makes sleeping instantaneous and writes down how long each nap
# was meant to be. Tests that care about politeness read RecordedSleeps.all;
# every other test just runs fast.
module RecordedSleeps
  class << self
    def all = @all ||= []
    def reset = @all = []
    def record(seconds) = all << seconds
  end
end

module Kernel
  def sleep(seconds = nil)
    RecordedSleeps.record(seconds)
    0
  end
end
