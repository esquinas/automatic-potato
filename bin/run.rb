#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require_relative "../lib/vo_cinema"

# The order does not matter. Every provider is asked about every cinema, and
# where they describe the same screening Reconciliation unions their claims
# rather than letting one of them win.
VoCinema::WeeklyNotifier.new(
  showtimes: [VoCinema::Showtimes::Sensacine.new, VoCinema::Showtimes::Yelmo.new],
  movies_db: VoCinema::Movies::Tmdb.new,
  messenger: VoCinema::Messengers::Telegram.new,
  cinemas:   VoCinema::Cinema.all
).run
