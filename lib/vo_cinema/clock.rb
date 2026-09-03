# frozen_string_literal: true

require "yaml"
require "tzinfo"

module VoCinema
  # What day it is where the cinemas are.
  #
  # Not the same as Date.today, which reads the timezone of whatever machine
  # happens to be running. A GitHub runner is on UTC, so a run started at 00:45
  # in Gijón sees yesterday's date: it asks the providers for a day whose
  # programme has already been shown, never asks about the last day of the
  # week, and heads the digest with a range that is off by one. The scheduled
  # cron fires around noon local and so never noticed; a manual run late in
  # the evening does.
  #
  # The zone is configuration rather than a constant because it belongs with
  # the cinemas it describes — a service pointed at another city changes one
  # file. It is an IANA name, so the CET/CEST switch is tzdata's problem.
  module Clock
    CONFIG = File.expand_path("../../config/cinemas.yml", __dir__)
    FALLBACK = "Europe/Madrid"

    def self.today(path: CONFIG) = zone(path).now.to_date

    def self.zone(path = CONFIG) = TZInfo::Timezone.get(name(path))

    # A config without a timezone still runs, on the city the service was
    # written for, rather than failing a Wednesday digest over a missing line.
    def self.name(path = CONFIG) = YAML.load_file(path)["timezone"] || FALLBACK
  end
end
