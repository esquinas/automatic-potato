#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require_relative "../lib/sensacine_client"
require_relative "../lib/tmdb_client"
require_relative "../lib/telegram_messenger"
require_relative "../lib/weekly_notifier"

CINEMAS = YAML.load_file(File.join(__dir__, "..", "config", "cinemas.yml"))["cinemas"].freeze

WeeklyNotifier.new(
  showtimes: SensacineClient.new,
  movies_db: TmdbClient.new,
  messenger: TelegramMessenger.new,
  cinemas:   CINEMAS
).run
