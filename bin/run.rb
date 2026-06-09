#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require_relative "../lib/cinema"
require_relative "../lib/sensacine_client"
require_relative "../lib/tmdb_client"
require_relative "../lib/html_formatter"
require_relative "../lib/telegram_messenger"
require_relative "../lib/weekly_notifier"

CINEMAS = YAML.load_file(File.join(__dir__, "..", "config", "cinemas.yml"))["cinemas"]
             .map { |entry| Cinema.from_h(entry) }.freeze

WeeklyNotifier.new(
  showtimes: SensacineClient.new,
  movies_db: TmdbClient.new,
  formatter: HtmlFormatter.new,
  messenger: TelegramMessenger.new,
  cinemas:   CINEMAS
).run
