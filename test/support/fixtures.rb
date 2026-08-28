# frozen_string_literal: true

require "json"

# Reads the payloads under test/fixtures/, which are real responses captured
# from the live providers rather than invented ones.
#
# To refresh them: run the "Capture API fixtures" workflow and copy the blocks
# it prints between its BEGIN/END markers into the matching file. bin/
# capture_fixtures.rb is the script behind it.
module Fixtures
  DIR = File.expand_path("../fixtures", __dir__)

  def self.read(name)  = File.read(path(name))
  def self.parse(name) = JSON.parse(read(name))
  def self.path(name)  = File.join(DIR, name)
end
