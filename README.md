# Gijón VO Cinema

<img src="assets/logo.png" alt="VOSE" width="48" height="48" style="vertical-align: middle; margin-right: 0.5em;">

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

## Output Format

### Telegram (HTML formatting with pre-formatted text)
```
Yelmo Cines Ocimax Gijón — 2026-06-08 → 2026-06-14

La Sustancia ★ 7.5
<pre>
• Fri →        18:15
• Sat → 16:15, 18:15
• Sun → 16:15, 18:15
</pre>

Didi ★ 6.2
<pre>
• Fri → 19:30
• Sat → 19:30
• Sun → 19:30
</pre>
```

### Stdout (plain text, for local testing)
```
Yelmo Cines Ocimax Gijón — 2026-06-08 → 2026-06-14

La Sustancia (Substance, The) 7.5
Fri: 18:15
Sat: 16:15, 18:15
Sun: 16:15, 18:15

Didi 6.2
Fri: 19:30
Sat: 19:30
Sun: 19:30
```

Times are right-aligned in Telegram for clean column alignment. Each cinema is followed by a week date range, then films with ratings and session times.
