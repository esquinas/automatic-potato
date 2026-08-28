#!/usr/bin/env ruby
# frozen_string_literal: true

# The whole suite: `ruby test.rb`. Add VERBOSE=1 to see what the clients print
# while they work.
#
# The tests live in test/, one file per class, plus test/end_to_end_test.rb
# which drives the real pipeline from real provider payloads to a delivered
# Telegram digest.
#
# Two conventions hold everywhere, and between them they are what let the suite
# survive a refactor of the code it covers:
#
#   1. The only thing faked is the network. FakeHttp intercepts Net::HTTP and
#      nothing else — no test names a method the project owns, so renaming,
#      moving or reorganising anything above the socket leaves the suite green.
#
#   2. Collaborators are small hand-written fakes, never strict mocks with call
#      counts and argument expectations. A test fails when the digest is wrong,
#      not when the notifier decides to ask TMDB in a different order.
#
# Expressiveness beats reuse in here. A test that repeats its setup in full,
# and can be read start to finish without scrolling to a shared helper, is the
# one worth having.

require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"
  gem "minitest", "~> 5"
end

require "minitest/autorun"

require_relative "test/support/no_real_sleeping"
require_relative "test/support/fixtures"
require_relative "test/support/fake_http"
require_relative "test/support/rendered_digest"
require_relative "test/support/service_test"
require_relative "test/support/fakes"

FakeHttp.block_real_connections

Dir[File.join(__dir__, "test", "*_test.rb")].sort.each { |test_file| require test_file }
