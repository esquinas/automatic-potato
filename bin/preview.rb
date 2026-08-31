#!/usr/bin/env ruby
# frozen_string_literal: true

# The whole weekly run, printed instead of sent.
#
# Same providers, same TMDB client, same notifier as bin/run.rb — only the
# messenger differs, so what comes out is what subscribers would have got. That
# makes it the way to read the agreement block (see CLAUDE.md, "Reading the
# agreement block") without costing subscribers a duplicate digest, which is
# enough friction that nobody would ever look.
#
# It cannot post: no Telegram messenger is ever built, so no token is read and
# no request to Telegram exists to make. The workflow leans on that by passing
# only TMDB_API_KEY to this step.

require "bundler/setup"
require_relative "../lib/vo_cinema"

# The order does not matter. Every provider is asked about every cinema, and
# where they describe the same screening Reconciliation unions their claims
# rather than letting one of them win.
VoCinema::WeeklyNotifier.new(
  showtimes: [VoCinema::Showtimes::Sensacine.new, VoCinema::Showtimes::Yelmo.new],
  movies_db: VoCinema::Movies::Tmdb.new,
  messenger: VoCinema::Messengers::Stdout.new,
  cinemas:   VoCinema::Cinema.all
).run
