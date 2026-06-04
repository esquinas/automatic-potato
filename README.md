# Gijón VO Cinema

Queries SensaCine's internal JSON API for original-version screenings across Gijón's cinemas, enriches each film with its TMDB rating, and delivers a formatted digest to Telegram. **Executes automatically every Monday at 14:00 UTC via GitHub Actions.** Cinemas are configured in `config/cinemas.yml`.

## Installation

Install [mise](https://mise.jdx.dev) to manage Ruby versions and environment variables:

```bash
mise install
ruby test.rb          # run tests
ruby bin/run.rb       # run the notifier
```

Configure secrets in `.mise.toml` — see the `[env]` section for required variables (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `TMDB_API_KEY`). GitHub Actions reads them from repository secrets instead.

## Local Development

To test locally, set environment variables in `.mise.toml` or your shell, then run `ruby bin/run.rb`.
