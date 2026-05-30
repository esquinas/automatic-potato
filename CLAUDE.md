# Gijón VO Cinema Weekly Notifier

A Ruby script that queries SensaCine's internal JSON API weekly for non-dubbed screenings in Gijón, enriches results with TMDB ratings, and delivers a Telegram digest every Monday morning.

## Commands

```bash
ruby test.rb          # run all tests (minitest 5, inline Gemfile)
ruby bin/run.rb       # run the notifier (requires env vars below)
```

## Secrets (GitHub Actions + local `.env`)

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_CHAT_ID`
- `TMDB_API_KEY`

Each class reads its own secrets from ENV as default keyword arguments — plain `.new` with no args works everywhere.

## Architecture

```
lib/
  http_client.rb        # shared HTTP module (retry, jitter) — included by clients
  sensacine_client.rb   # fetches showtimes from SensaCine internal JSON API
  tmdb_client.rb        # searches TMDB for original title + rating
  telegram_messenger.rb # sends message via Telegram Bot API
  stdout_messenger.rb   # sends message to stdout (dev/testing)
  film.rb               # mutable PORO: localized_title + year always set; title filled after TMDB lookup
  screening_session.rb  # Data.define: film, date, starts_at, original_version?
  rating.rb             # Data.define with .null sentinel; to_s/to_str safe for string interpolation
  weekly_notifier.rb    # orchestrator: collect → enrich → render → send
bin/run.rb              # thin entry point: four plain .new calls
config/cinemas.yml      # user-editable cinema list (name, SensaCine ID, url, check_vo flag)
test.rb                 # minitest 5 with inline Gemfile, stubbed HTTP
.github/workflows/
  test.yml              # runs ruby test.rb on every push and PR
  weekly.yml            # Monday 08:00 UTC cron + workflow_dispatch
```

### Naming conventions

- `*Client` — queries an external API (`SensacineClient`, `TmdbClient`)
- `*Messenger` — delivers output (`TelegramMessenger`, `StdoutMessenger`)
- All Clients and all Messengers share the same call site: plain `.new`. Classes with no config use `def initialize(**) = nil`.
- Each class exposes a `DOMAIN` constant at the top for its base URL.

### `WeeklyNotifier` interface

```ruby
WeeklyNotifier.new(showtimes:, movies_db:, messenger:, cinemas:).run(today: Date.today)
```

Any conforming Client or Messenger can be swapped in without touching the orchestrator.

## SensaCine API

```
GET https://www.sensacine.com/_/showtimes/theater-{ID}/d-{YYYY-MM-DD}/p-1/
```

Headers required: `Referer: https://www.sensacine.com/cines/cine/`, realistic `User-Agent`, `Accept: application/json`.

Response shape: `results[].movie.title`, `results[].showtimes.{original,dubbed,local}[].startsAt`.

**VO filter:** use the bucket key, not `diffusionVersion` — live data shows dubbed films have `diffusionVersion=nil` and originals have `"ORIGINAL"`, making the field unreliable. `original` and `local` buckets = VO; `dubbed` = excluded.

The `check_vo` flag in `cinemas.yml` controls whether `WeeklyNotifier` applies the VO filter for a given venue (some venues screen only VO by policy, so no filter is needed).

**Pagination:** the API paginates; `pagination.totalPages` indicates total. Current implementation fetches page 1 only — sufficient for most venues.

The old `api.sensacine.com/rest/v3/showtimelist` endpoint is dead (403 since ~2021). Do not use it.

## TMDB matching strategy

1. Search by Spanish title + year (`/3/search/movie?query=...&year=...&language=es-ES`).
2. If top two results have rating ratio < 2×, return `Rating.null` (ambiguous match — no rating shown).
3. No cache: ~10 films/week is well within TMDB free tier (50 req/s).

`TmdbClient` exposes two pure queries: `fetch_original_title(film)` and `rating_for(film)`. Mutation (`film.title =`) stays in `WeeklyNotifier`.
