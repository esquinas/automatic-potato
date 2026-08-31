# frozen_string_literal: true

source "https://rubygems.org"

# Autoloading, so a new class needs a file in the right place and nothing else.
gem "zeitwerk", "~> 2.6"

# The agreement report writes CSV rows. Named explicitly because csv stops
# being a default gem in Ruby 3.4 and warns about it from 3.3.
gem "csv", "~> 3.3"

# "Today" means today in Gijón, not on whatever machine is running. Ruby can
# only reach a named zone through the process TZ, which a GitHub runner sets
# to UTC — so the rules come from here instead.
gem "tzinfo", "~> 2.0"

group :test do
  gem "minitest", "~> 5"
end
