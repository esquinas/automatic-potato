#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require_relative "../lib/sensacine_adapter"
require_relative "../lib/tmdb_adapter"
require_relative "../lib/telegram_adapter"
require_relative "../lib/weekly_notifier"

CINEMAS = YAML.load_file(File.join(__dir__, "..", "config", "cinemas.yml"))["cinemas"].freeze

WeeklyNotifier.new(
  sensacine: SensacineAdapter.new,
  tmdb:      TmdbAdapter.new(api_key: ENV.fetch("TMDB_API_KEY")),
  telegram:  TelegramAdapter.new(
    token:   ENV.fetch("TELEGRAM_BOT_TOKEN"),
    chat_id: ENV.fetch("TELEGRAM_CHAT_ID")
  ),
  cinemas: CINEMAS
).run
