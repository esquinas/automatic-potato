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
  movies_db: TmdbClient.new(api_key: ENV.fetch("TMDB_API_KEY")),
  messenger: TelegramMessenger.new(
    token:   ENV.fetch("TELEGRAM_BOT_TOKEN"),
    chat_id: ENV.fetch("TELEGRAM_CHAT_ID")
  ),
  cinemas: CINEMAS
).run
