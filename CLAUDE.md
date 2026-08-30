# Gijón VO Cinema Weekly Notifier

A Ruby script that queries SensaCine's internal JSON API weekly for non-dubbed screenings in Gijón, enriches results with TMDB ratings, and delivers a Telegram digest on Monday and Friday mornings.

## Git workflow

Every change gets its own branch cut from the latest `master`. Never add commits to an existing feature branch when asked to make a new, separate change.

```bash
git fetch origin master
git checkout origin/master -b <branch-name>
# make changes, commit, push
git push -u origin <branch-name>
```

Each branch maps to exactly one PR. When master moves forward (merged PRs), always rebase or re-cut before opening a new PR so it has a single, clean commit on top of current master.

**One exception:** a refactor that wins back the RubyCritic score the change cost, on the code that change touched or exposed, rides along on its branch as a commit of its own.

## Commands

```bash
ruby test.rb              # run all tests (minitest 5, inline Gemfile)
VERBOSE=1 ruby test.rb    # ...and let the clients' own logging through
ruby bin/run.rb           # run the notifier (requires env vars below)
ruby bin/diagnose.rb      # check the tokens and probe SensaCine live
```

## Secrets (GitHub Actions + local `.env`)

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_CHAT_ID`
- `TMDB_API_KEY`

Each class reads its own secrets from ENV as default keyword arguments — plain `.new` with no args works everywhere.

## Architecture

```
lib/
  http_client.rb        # shared HTTP module (one retry, jitter) — included by clients
  sensacine_client.rb   # fetches showtimes from SensaCine internal JSON API
  tmdb_client.rb        # searches TMDB for original title + rating
  telegram_messenger.rb # sends message via Telegram Bot API
  stdout_messenger.rb   # sends message to stdout (dev/testing)
  film.rb               # mutable PORO: localized_title + year always set; title filled after TMDB lookup
  screening_session.rb  # Data.define: film, date, starts_at, original_version?; #slot identifies a screening across providers
  rating.rb             # Data.define with .null sentinel; to_s/to_str safe for string interpolation
  yelmo_client.rb       # authoritative VO source for Yelmo Ocimax Gijón
  cinema_listing.rb     # Data.define: one cinema's week, enriched and ready to print
  digest_renderer.rb    # pure: turns listings into the Telegram message
  timetable.rb          # pure: one film's week, grouped by day and aligned into a column
  weekly_notifier.rb    # orchestrator: collect → enrich → render → send
bin/
  run.rb                # thin entry point: four plain .new calls
  diagnose.rb           # token health check + live SensaCine probe
  capture_fixtures.rb   # prints live provider payloads for refreshing fixtures
config/cinemas.yml      # user-editable cinema list (name, SensaCine ID, url, check_vo flag)
.mise.toml              # Ruby version (3.3) pinned for mise
test.rb                 # entry point: inline Gemfile, then loads test/
test/
  support/              # FakeHttp, fixtures loader, digest reader, fakes
  fixtures/             # real captured provider payloads (see its README)
  *_test.rb             # one file per class, plus end_to_end_test.rb
.github/workflows/
  test.yml              # runs ruby test.rb on every push and PR
  rubycritic.yml        # code quality gate on lib/ (minimum score 87)
  weekly.yml            # Monday and Friday 11:00 Gijón cron + workflow_dispatch
  diagnose.yml          # workflow_dispatch token/API health check
  capture-fixtures.yml  # workflow_dispatch: print live payloads for fixtures
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
GET https://www.sensacine.com/_/showtimes/theater-{ID}/d-{YYYY-MM-DD}/
```

Headers required: `Referer: https://www.sensacine.com/cines/cine/`, realistic `User-Agent`, `Accept: application/json`.

Response shape: `results[].movie.title`, `results[].showtimes.{original,dubbed,local}[].startsAt`.

**VO filter — both signals count.** A screening is original version if its bucket is one of `VO_BUCKETS` (`original`, `original_st`, `original_sme`, `local`, `local_st`, `local_sme`) **or** its `diffusionVersion` is `"ORIGINAL"`. The bucket alone is not enough: SensaCine misfiles some subtitled prints under `dubbed`, where only `diffusionVersion` gives them away — that is how Yelmo's VOSE screenings arrive, and it is what `test_a_screening_misfiled_as_dubbed_is_rescued_by_its_diffusion_version` pins down.

`diffusionVersion` is not enough on its own either, and its vocabulary has moved: it was observed as `nil` on dubbed screenings when the filter was first written, and the 2026-08-28 capture shows `"DUBBED"`. Treat a new value there as a change worth looking at rather than as noise.

The `check_vo` flag in `cinemas.yml` controls whether `WeeklyNotifier` applies the VO filter for a given venue (some venues screen only VO by policy, so no filter is needed).

**Pagination:** a busy day is split into pages of ten, with `pagination.totalPages` saying how many. Extra pages are requested as `?page={n}`; the `/p-{n}/` *path* segment is not supported and makes the endpoint return empty results.

**An empty day means expired, not absent.** The endpoint lists only screenings
you could still buy a ticket for, so a day drains as its programme runs: by
late evening every screening has gone and the response is `error: true`,
`message: "next.showtime.on"`, `results: []`, with a `nextDate`. That is the
API saying *the next showing is on X*, not *this day had no cinema*. How much
of a day you see depends entirely on the hour you ask.

Consequences, all of which are easy to get wrong:

- **Never word output as "no sessions"** for a day or venue that came back
  empty. The screenings existed; they have already been shown. Say that the
  programme has passed, or that there is nothing left to book.
- **Judge an empty result by the clock.** Empty for *today* late in the day is
  normal. Empty for a *future* day cannot be expiry, so that is the signal
  worth alarming on.
- **`error: true` with a `nextDate` is a healthy answer.** Missing `nextDate`,
  a non-200, or an unparseable body is not. Do not lump them together.
- The cron fires at 11:00 in Gijón, ahead of the day's first screening (the
  earliest seen at Ocimax is 16:00), so day zero reaches subscribers whole. It
  used to fire at 16:00 local, which silently dropped every matinee. GitHub's
  cron is UTC only and Gijón changes offset twice a year, so `weekly.yml` fires
  at both 09:00 and 10:00 UTC and drops whichever one is not 11:00 locally.
- The digest says so out loud rather than implying a complete day:
  `WeeklyNotifier#closing_notes` ends every message with a line explaining that
  today lists only what is still to come, and names a venue with nothing left
  without claiming it programmed nothing.
- `test/fixtures/sensacine/nothing_left_that_day.json` was captured at 01:26
  local asking about the previous day, and records the behaviour.

**Release year:** the year lives at `movie.data.productionYear` — that is the year TMDB files a film under, and it is what narrows the TMDB search. `SensacineClient` used to read `movie.release.year`, which the feed does not have, so `Film#year` was `nil` for every SensaCine film and every match was looser than intended. An entry without a production year falls back to the earliest date under `movie.releases[]` (`releaseDate.date`, `YYYY-MM-DD`), and a film the feed dates nowhere still gets listed — TMDB is simply asked about it without the year filter.

Only SensaCine dates a film; Yelmo's payload carries no year at all. Since `Film#==` counts the year, the same film from the two providers would otherwise be two films — printed twice at Ocimax with its week split between the entries. `WeeklyNotifier#lend_known_years` closes that at merge time by giving Yelmo's copy the year SensaCine knows for the same title, which also buys the Yelmo-only screenings a narrowed TMDB search.

The old `api.sensacine.com/rest/v3/showtimelist` endpoint is dead (403 since ~2021). Do not use it.

## TMDB matching strategy

1. Search by Spanish title + year (`/3/search/movie?query=...&year=...&language=es-ES`).
2. If the top result has zero votes, return `Rating.null`.
3. If top two results have rating ratio < 2×, return `Rating.null` (ambiguous match — no rating shown).
4. No cache: ~10 films/week is well within TMDB free tier (50 req/s).

`TmdbClient` exposes three pure queries: `fetch_original_title(film)`, `rating_for(film)`, and `spanish_original?(film)` (`original_language == "es"` on the top search result). Mutation (`film.title =`) stays in `WeeklyNotifier`.

## Tests

`ruby test.rb` loads `test/support/` and then every `test/*_test.rb`. Two
conventions hold throughout, and between them they are what lets the suite
survive a refactor of the code it covers:

1. **Only the network is faked.** `FakeHttp` intercepts `Net::HTTP.start` and
   nothing else, so URL building, headers, the retry loop, JSON parsing and
   bucket classification all run for real. No test names a method the project
   owns. Real connections are blocked outright for the whole run, so a test
   that forgets to stub fails instead of quietly reaching the internet.
2. **Collaborators are small hand-written fakes**, never strict mocks with call
   counts and argument order. A test fails when the digest is wrong, not when
   the notifier asks TMDB in a different order. The fakes record what they were
   asked, so a test that genuinely cares about call counts says so out loud.

Assertions are about what the digest *says*, not how it is punctuated —
`RenderedDigest` strips the markup and answers questions about films, times and
venues. Expressiveness beats reuse: a test that repeats its setup in full and
reads start to finish without scrolling to a helper is the one worth having.

Fixtures under `test/fixtures/` are real captured payloads. Refresh them with
the **Capture API fixtures** workflow, which prints live responses to the job
log between `===== BEGIN fixture: … =====` markers; see
`test/fixtures/README.md`.

## Design decisions

**One film's timetable is its own object** — `Timetable` takes a film's
sessions and lays them out: grouped by day, right-aligned into a column, and
collapsed to a single "All week" line when the film shows every day. It emits
plain text and knows nothing about Telegram markup, so `DigestRenderer` keeps
deciding how the digest is dressed and stops having to know how a column of
times is squared up. The extraction is what took `DigestRenderer` off a C
rating; as with the split below, the test suite needed no edit.

**Rendering is separate from orchestrating** — `WeeklyNotifier` talks to the
providers, decides which screenings survive, and enriches each film;
`DigestRenderer` turns the result into text and asks nobody anything. The
renderer is a pure function of its input, so the digest can be reasoned about
without a single stub, and the notifier is free of every string of markup.
`CinemaListing` is what passes between them: one venue's week, already
enriched. The split took `lib/` from 85.97 to 88.54 on RubyCritic, and — the
part worth noticing — the test suite needed no edit at all, because it asserts
on what the digest says rather than on how it is assembled.

**`Film` is a mutable PORO** — `title` starts `nil` and is filled after TMDB lookup. `Data.define` was rejected here because immutability would require propagating new instances across all `ScreeningSession` references that already hold the original `Film`.

**`ScreeningSession` is `Data.define`** — fully resolved at construction time, never mutated.

**`original_version?` resolved by the client** — `VO_BUCKETS.include?(bucket)` lives in `SensacineClient`. Domain objects stay free of provider-specific string vocabulary (`"original"`, `"local"`, `"dubbed"`).

**Spanish-original films fall back to a TMDB check in `WeeklyNotifier`** — a Spanish production is never dubbed or subtitled, so no provider (`SensacineClient`'s buckets, `YelmoClient`'s `VO_LANGUAGES` tags) ever marks its plain screening as VO; its only version simply *is* the original one. When `check_vo` would otherwise drop a session, `WeeklyNotifier#collect_sessions` asks `TmdbClient#spanish_original?(film)` before excluding it, and keeps the session if the film's TMDB `original_language` is `"es"`. Results are memoized per `Film` for the run to avoid redundant TMDB calls across the week's sessions.

**`fetch_theater_movie_sessions` takes no filter arg** — the client always returns all sessions with `original_version?` set. The caller (`WeeklyNotifier`) filters with `.select(&:original_version?)` when `check_vo` is true. This keeps the client a pure data source.

**`Rating` is a NullObject** — `Rating.null` returns a frozen instance with `score: nil`. Both present and null ratings implement `to_s` / `to_str`, so callers push them into a parts array and call `.join(" ").strip` — no conditionals, no `nil` checks. `Rating.null.to_s` returns `""`, which `strip` absorbs silently. `to_str` enables implicit coercion in `String#+` and `Array#join`.

**Command-query separation on `TmdbClient`** — `fetch_original_title` and `rating_for` are pure queries. Mutation (`film.title =`) stays in `WeeklyNotifier`, which owns the enrichment lifecycle.

**Unified constructor signatures** — all `*Client` and `*Messenger` classes share the same call site: plain `.new`. Classes that need no config (`SensacineClient`, `StdoutMessenger`) declare `def initialize(**) = nil` to accept and silently discard any kwargs, keeping the interface consistent for callers that pass options uniformly.

**`DOMAIN` constant per class** — base URL extracted to the top of each file. Renaming a service is a single-line edit, and derived strings (headers, paths) reference `DOMAIN` via interpolation so they update automatically.

**`HttpClient` is a module, not a base class** — shared retry-with-jitter logic is included by `SensacineClient`, `TmdbClient` and `YelmoClient`. The module keeps it encapsulated without imposing an inheritance hierarchy. GET and POST differ only in the request they build, so they hand a block to one `with_one_retry`: attempt, pause, and on anything but a 200 attempt once more behind a much longer pause. The block builds a fresh request each time — a `Net::HTTP` request that has been on the wire once is not safe to send again.

**A film is compared across providers by `Film#key`** — the localized title downcased and stripped, because SensaCine and Yelmo disagree about capitals and stray spaces. `ScreeningSession#slot` (`[date, starts_at, film.key]`) is built on it and is what `WeeklyNotifier#merge_sessions` groups by. Note that `Film#==` is stricter: it counts the year too, so `Nosferatu` 1922 and 2024 stay two films.

**`WeeklyNotifier` uses generic dependency names** — `showtimes:`, `movies_db:`, `messenger:` rather than `sensacine:`, `tmdb:`, `telegram:`. Any conforming implementation (e.g. `StdoutMessenger`, a future `ImdbClient`) plugs in without changing the orchestrator.
