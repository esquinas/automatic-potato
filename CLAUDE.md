# Gijón VO Cinema Weekly Notifier

A Ruby script that queries SensaCine's internal JSON API weekly for non-dubbed screenings in Gijón, enriches results with TMDB ratings, and delivers a Telegram digest every Monday morning.

## Git workflow

Every change gets its own branch cut from the latest `master`. Never add commits to an existing feature branch when asked to make a new, separate change.

```bash
git fetch origin master
git checkout origin/master -b <branch-name>
# make changes, commit, push
git push -u origin <branch-name>
```

Each branch maps to exactly one PR. When master moves forward (merged PRs), always rebase or re-cut before opening a new PR so it has a single, clean commit on top of current master.

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
.mise.toml              # Ruby version (3.3) pinned for mise
test.rb                 # minitest 5 with inline Gemfile, stubbed HTTP
.github/workflows/
  test.yml              # runs ruby test.rb on every push and PR
  weekly.yml            # Monday 14:00 UTC cron + workflow_dispatch
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
2. If the top result has zero votes, return `Rating.null`.
3. If top two results have rating ratio < 2×, return `Rating.null` (ambiguous match — no rating shown).
4. No cache: ~10 films/week is well within TMDB free tier (50 req/s).

`TmdbClient` exposes two pure queries: `fetch_original_title(film)` and `rating_for(film)`. Mutation (`film.title =`) stays in `WeeklyNotifier`.

## Design decisions

**`Film` is a mutable PORO** — `title` starts `nil` and is filled after TMDB lookup. `Data.define` was rejected here because immutability would require propagating new instances across all `ScreeningSession` references that already hold the original `Film`.

**`ScreeningSession` is `Data.define`** — fully resolved at construction time, never mutated.

**`original_version?` resolved by the client** — `VO_BUCKETS.include?(bucket)` lives in `SensacineClient`. Domain objects stay free of provider-specific string vocabulary (`"original"`, `"local"`, `"dubbed"`).

**`fetch_theater_movie_sessions` takes no filter arg** — the client always returns all sessions with `original_version?` set. The caller (`WeeklyNotifier`) filters with `.select(&:original_version?)` when `check_vo` is true. This keeps the client a pure data source.

**`Rating` is a NullObject** — `Rating.null` returns a frozen instance with `score: nil`. Both present and null ratings implement `to_s` / `to_str`, so callers push them into a parts array and call `.join(" ").strip` — no conditionals, no `nil` checks. `Rating.null.to_s` returns `""`, which `strip` absorbs silently. `to_str` enables implicit coercion in `String#+` and `Array#join`.

**Command-query separation on `TmdbClient`** — `fetch_original_title` and `rating_for` are pure queries. Mutation (`film.title =`) stays in `WeeklyNotifier`, which owns the enrichment lifecycle.

**Unified constructor signatures** — all `*Client` and `*Messenger` classes share the same call site: plain `.new`. Classes that need no config (`SensacineClient`, `StdoutMessenger`) declare `def initialize(**) = nil` to accept and silently discard any kwargs, keeping the interface consistent for callers that pass options uniformly.

**`DOMAIN` constant per class** — base URL extracted to the top of each file. Renaming a service is a single-line edit, and derived strings (headers, paths) reference `DOMAIN` via interpolation so they update automatically.

**`HttpClient` is a module, not a base class** — shared retry-with-jitter logic is included by `SensacineClient` and `TmdbClient`. The module keeps it encapsulated without imposing an inheritance hierarchy.

**`WeeklyNotifier` uses generic dependency names** — `showtimes:`, `movies_db:`, `messenger:` rather than `sensacine:`, `tmdb:`, `telegram:`. Any conforming implementation (e.g. `StdoutMessenger`, a future `ImdbClient`) plugs in without changing the orchestrator.
