#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require_relative "../lib/vo_cinema"

# Providers run least to most authoritative: SensaCine lists every cinema in
# Gijón, and Yelmo is believed over it about its own.
VoCinema::WeeklyNotifier.new(
  showtimes: [VoCinema::Showtimes::Sensacine.new, VoCinema::Showtimes::Yelmo.new],
  movies_db: VoCinema::Movies::Tmdb.new,
  messenger: VoCinema::Messengers::Telegram.new,
  cinemas:   VoCinema::Cinema.all
).run
