# Gijón VO Cinema

<img src="assets/logo.png" alt="VOSE" width="48" height="48" style="vertical-align: middle; margin-right: 0.5em;">

Queries SensaCine's internal JSON API for original-version screenings across Gijón's cinemas, enriches each film with its TMDB rating, and delivers a formatted digest to Telegram. **Executes automatically every Monday and Friday at 11:00 Gijón time via GitHub Actions.** Cinemas are configured in `config/cinemas.yml`.

## Installation

Install [mise](https://mise.jdx.dev) to manage Ruby versions and environment variables:

```bash
mise install
bundle install
ruby test.rb         # run tests
ruby bin/run.rb      # run the notifier
```

Tests are offline and take under a second: `FakeHttp` intercepts `Net::HTTP` and replays real provider responses captured under `test/fixtures/`. Refresh those with the **Capture API fixtures** GitHub Action, which prints live SensaCine, Yelmo and TMDB payloads to its job log.

Configure secrets in `.mise.toml` — see the `[env]` section for required variables (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `TMDB_API_KEY`). GitHub Actions reads them from repository secrets instead.

## Local Development

To test locally, set environment variables in `.mise.toml` or your shell, then run `ruby bin/run.rb`.
