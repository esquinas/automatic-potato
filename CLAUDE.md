# Gijón VO Cinema Weekly Notifier

A Ruby script that asks two cinema listings — SensaCine and Yelmo, both internal JSON APIs — for the week's non-dubbed screenings in Gijón, reconciles what they say into one programme, enriches it with TMDB ratings, and delivers a Telegram digest on Monday and Friday mornings.

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
ruby bin/preview.rb       # ...the same run printed instead of sent; needs only TMDB_API_KEY
ruby bin/diagnose.rb      # check the tokens and probe SensaCine live
```

## Secrets (GitHub Actions + local `.env`)

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_CHAT_ID`
- `TMDB_API_KEY`

Each class reads its own secrets from ENV as default keyword arguments — plain `.new` with no args works everywhere.

## Architecture

```
Gemfile                 # zeitwerk, csv, tzinfo (runtime), minitest (test)
lib/
  vo_cinema.rb          # sets up Zeitwerk; the only require_relative in the project
  vo_cinema/
    cinema.rb           # Data.define: one venue as config/cinemas.yml describes it
    clock.rb            # what day it is where the cinemas are, not where the process runs
    film.rb             # mutable PORO: localized_title + director read from the feed; title filled after TMDB
    rating.rb           # Data.define with .null sentinel; to_s/to_str safe for interpolation
    screening_session.rb# Data.define: film, date, starts_at, original_version?
    cinema_listing.rb   # Data.define: one cinema's week, enriched and ready to print
    reconciliation.rb   # pure: several providers' accounts of one week, read as one
    reconciliation/record.rb       # one provider's account of one screening, with its name
    reconciliation/match.rb        # the film those records turned out to describe
    reconciliation/shared_years.rb # lends SensaCine's years to Yelmo's undated copies
    agreement.rb        # pure: how much the providers contradicted each other
    agreement_report.rb # the CSV health block the run log carries
    weekly_notifier.rb  # orchestrator: collect → enrich → render → send
    http/
      client.rb         # the only code that touches the network: retry, pacing, shared headers
    showtimes/
      sensacine.rb      # fetches a theatre-day, follows pagination
      sensacine/day.rb  # reads one day's buckets and clock times into ScreeningSessions
      sensacine/movie.rb# reads one entry's title, year and director into a Film
      yelmo.rb          # fetches a city once, caches it
      yelmo/listing.rb  # reads one cinema's formats and times into ScreeningSessions by day
      yelmo/movie.rb    # reads one film's title and director into a Film
    movies/
      tmdb.rb           # original title, rating, and whether a film is a Spanish production
    digest/
      renderer.rb       # pure: turns listings into the Telegram message
      timetable.rb      # pure: one film's week, grouped by day and aligned into a column
    messengers/
      telegram.rb       # posts the digest; owns Telegram's length limit
      stdout.rb         # prints the digest; strips the markup a terminal cannot use
bin/
  run.rb                # thin entry point
  preview.rb            # the same run, printed instead of sent; cannot post
  diagnose.rb           # token health check + live SensaCine probe
  capture_fixtures.rb   # prints live provider payloads for refreshing fixtures
  probe_identity.rb     # asks how the providers name the same film
config/cinemas.yml      # user-editable: the cinemas' timezone, then the list itself
.mise.toml              # Ruby version (3.3) pinned for mise
test.rb                 # entry point: loads test/support/ then every test/**/*_test.rb
test/
  support/              # FakeHttp, fixtures loader, digest reader, fakes, Tee
  fixtures/             # real captured provider payloads (see its README)
  **/*_test.rb          # mirrors lib/, plus end_to_end_test.rb
.github/workflows/
  test.yml              # runs ruby test.rb on every pull request and on master
  rubycritic.yml        # code quality gate on lib/ (minimum score 92)
  weekly.yml            # Monday and Friday 11:00 Gijón cron; dispatch takes dry_run
  diagnose.yml          # workflow_dispatch token/API health check
  capture-fixtures.yml  # workflow_dispatch: print live payloads for fixtures
  programme-watch.yml   # Tue/Wed/Sat dry run; temporary, settles the fill-in question
```

### Naming conventions

- Folders name layers, and Zeitwerk maps them to namespaces: `Showtimes::`
  providers, `Movies::` for TMDB, `Messengers::` for delivery, `Digest::` for
  rendering, `Http::` for the network. A new class needs a file in the right
  place and nothing else — there is no `require_relative` below `lib/vo_cinema.rb`.
- A provider answers `sessions_for(cinema, date)` and `name`; a messenger
  answers `send_message(text)`. Both are built with a plain `.new`. The name is
  what the agreement report calls it, spelled as the provider spells itself
  (`"SensaCine"`, `"Yelmo"`).
- Each class that talks to a service exposes a `DOMAIN` constant and its own
  `HEADERS`, composed from `Http::Client::BROWSER`.
- `VoCinema::Digest` deliberately shadows nothing: stdlib `::Digest` is still
  reachable, because no file inside the namespace refers to it unqualified.

### `WeeklyNotifier` interface

```ruby
VoCinema::WeeklyNotifier.new(
  showtimes: [Showtimes::Sensacine.new, Showtimes::Yelmo.new],  # order does not matter
  movies_db: Movies::Tmdb.new,
  messenger: Messengers::Telegram.new,
  cinemas:   Cinema.all
).run   # today: defaults to Clock.today — the cinemas' date, never Date.today
```

Every provider is asked about every cinema and answers with nothing for a venue
it does not cover — the notifier keeps no table of which provider runs what,
because each provider reads its own id out of the `Cinema`.

Where several describe the same screening they become one, and it is original
version **if any of them said so**. The order they are listed in changes
nothing. If a genuinely more authoritative provider ever turns up, it wants
conciliation logic of its own rather than a privileged place in this list.

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
- **Judge an empty result by the clock, and by which error came back.** Empty
  for *today* late in the day is expiry. Empty for a *future* day cannot be, but
  is still usually benign — there are exactly two error messages, and they mean
  different things:
  - `next.showtime.on`, **with** a `nextDate` — **not on sale yet** (or, for
    today, already shown). Ocimax reads this way for the back half of every
    week; see *Does the programme fill in mid-week?* below.
  - `no.showtime.error`, with an **empty** `nextDate` — **no film programme at
    all.** The municipal centres (`G02E8`, `G02E9`, `G02GD`) answer this way
    every day; they screen films only occasionally and SensaCine lists them
    regardless.

  So `error: true` is a healthy answer either way, and an empty `nextDate` is
  not on its own a fault. What is worth alarming on: a non-200, an unparseable
  body, a message that is neither of these two, or `no.showtime.error` from a
  venue that normally programmes.
- **Which day is "day zero" is `Clock.today`, not `Date.today`.** `Date.today`
  reads the timezone of the machine running, and a GitHub runner is on UTC — so
  a run just after midnight in Gijón asks about yesterday, never asks about the
  seventh day, and heads the digest with a range off by one. The 11:00 cron
  cannot trip this (09:00 and 10:00 UTC are the same calendar day as 11:00 in
  Gijón), which is exactly why a manual run late in the evening is what found
  it. `Clock` reads the zone from `config/cinemas.yml` and asks tzinfo.
- The cron fires at 11:00 in Gijón, ahead of the day's first screening (the
  earliest seen at Ocimax is 16:00), so day zero reaches subscribers whole.
  GitHub's cron is UTC only and Gijón changes offset twice a year, so
  `weekly.yml` fires at both 09:00 and 10:00 UTC and drops whichever one is not
  11:00 locally.
- The digest says so out loud rather than implying a complete day:
  `Digest::Renderer#closing_notes` ends every message with a line explaining
  that today lists only what is still to come, and names a venue with nothing
  left without claiming it programmed nothing.
- `test/fixtures/sensacine/nothing_left_that_day.json` records the behaviour.

**Release year:** the year lives at `movie.data.productionYear` — that is the year TMDB files a film under, and it is what narrows the TMDB search. There is no `movie.release.year`, whatever the shape suggests. An entry without a production year falls back to the earliest date under `movie.releases[]` (`releaseDate.date`, `YYYY-MM-DD`), and a film the feed dates nowhere still gets listed — TMDB is simply asked about it without the year filter.

Only SensaCine dates a film; Yelmo's payload carries no year at all. Since `Film#==` counts the year, the same film from the two providers would otherwise be two films — printed twice at Ocimax with its week split between the entries. `Reconciliation::SharedYears` closes that before anything is grouped, by giving Yelmo's copy the year SensaCine knows for the same title, which also buys the Yelmo-only screenings a narrowed TMDB search.

**Director:** `movie.credits[]` is a flat list of everyone who worked on the
film, each entry tagged with the job it did:

```json
{ "person":   { "firstName": "Chris", "lastName": "Columbus", "internalId": 3474 },
  "position": { "name": "DIRECTOR", "department": "DIRECTION" },
  "rank": 1 }
```

It is the one substantive field both providers publish, which is what lets a
film billed two different ways be matched — see *Matching a film across
providers*. `bin/capture_fixtures.rb` keeps only the `DIRECTOR` entries, because
the whole crew would bury a fixture but dropping the lot (as it used to) left no
fixture able to exercise the matching.

**An entry with no `movie.title` is dropped.** The feed carries some — the André
Rieu concert at Ocimax is one. Never substitute a placeholder: `"(untitled)"`
was one once, and TMDB answered it with `"Untitled Immaculate Reception Film"`,
which would have put a concert in front of subscribers under a stranger's name.
There is nothing to print, look up or match on. Where another provider covers
the same screening it arrives from there properly named, as that concert does
from Yelmo; at a SensaCine-only venue the screening is lost, which is the
accepted cost of not inventing one.

The old `api.sensacine.com/rest/v3/showtimelist` endpoint is dead (403 since ~2021). Do not use it.

## TMDB matching strategy

1. Search by Spanish title + year (`/3/search/movie?query=...&year=...&language=es-ES`).
2. If the top result has zero votes, return `Rating.null`.
3. If top two results have rating ratio < 2×, return `Rating.null` (ambiguous match — no rating shown).
4. Every search is cached for the life of the client, keyed by `[title, year]`.

`Movies::Tmdb` exposes three pure queries: `fetch_original_title(film)`, `rating_for(film)`, and `spanish_original?(film)` (`original_language == "es"` on the top search result). Mutation (`film.title =`) stays in `WeeklyNotifier`.

The cache is not about the rate limit — ~10 films a week is nowhere near TMDB's
50 req/s. It is that `fetch_original_title` and `spanish_original?` ask the
*same* query, and the notifier asks per screening rather than per film, so the
identical request went out two or three times over. A client is built once per
run, which makes it the right lifetime for the answers; nothing survives the
process, so a rating is never served stale.

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

**One film's timetable is its own object** — `Digest::Timetable` takes a film's
sessions and lays them out: grouped by day, right-aligned into a column, and
collapsed to a single "All week" line when the film shows every day. It emits
plain text and knows nothing about Telegram markup, so `Digest::Renderer` keeps
deciding how the digest is dressed and stops having to know how a column of
times is squared up.

**Each messenger owns its medium's constraints** — `Messengers::Telegram` holds
the 4096-character limit (enforced at 3800 with a "truncated" marker) because
that ceiling is a fact about Telegram, not about the digest; `Messengers::Stdout`
strips the markup, because a terminal cannot use `<b>` and `<pre>`.
`Digest::Renderer` writes one digest in Telegram's flavour and hands it over
whole, knowing nothing about where it goes. That keeps a local run readable
and stops a terminal digest being cut short for a limit that does not apply to
it. Adding a second renderer per channel was considered and rejected: with one
real channel there is nothing to generalise over yet, and a messenger that
adapts what it is given is far less machinery than a renderer per format.

**A positive VO signal beats a negative one, whoever it comes from** — the
providers' two claims are not equally reliable. Saying "original version" takes
information: a bucket named for it, a `diffusionVersion` of `"ORIGINAL"`, a
VOSE language tag. Saying "dubbed" is what a provider says when it has none,
which is why SensaCine files Yelmo's subtitled prints that way, and why Yelmo
labels a Spanish production `"ESPAÑOL"` when that print *is* the original. A
negative is an absence of evidence; a positive is evidence. So
`Reconciliation::Match#session` unions the positives, and the whole pipeline
reads the same way at every level — `Sensacine::Day` ORs bucket against
`diffusionVersion`, `WeeklyNotifier#surviving` ORs that against TMDB's
`spanish_original?`, and the merge ORs across providers.

The cost is accepted deliberately: a dubbed screening can reach the digest on
one provider's bad word. The box office states which print it is before anyone
pays, and cinemas guard hard against the opposite mistake — an audience
expecting dubbing and finding subtitles is the complaint they actually get.

**Fetching is separate from reading** — each provider is two classes: one that
makes requests (`Showtimes::Sensacine`, `Showtimes::Yelmo`) and one that turns
a payload into `ScreeningSession`s (`Sensacine::Day`, `Yelmo::Listing`). The
fetchers know about URLs, pagination and caching; the readers know about
buckets, language tags and timestamps and could not make a request if they
wanted to.

**Naming a film is separate from timing it** — each reader is itself two
classes: `Sensacine::Movie` and `Yelmo::Movie` answer with a `Film` (or `nil`
for an entry the feed never named), while `Sensacine::Day` and `Yelmo::Listing`
keep the buckets, language tags and clock. Naming a film means understanding
quite different corners of a payload — SensaCine spreads the year over
`movie.data` and `movie.releases[]` and buries the director in a flat credit
list — and none of that has anything to do with when the film is on. The two
providers now read the same shape, which is the point: a third would too.

**How to move the RubyCritic score**, learned from the three splits above, each
of which bought two to three points: the score is the average of the files'
ratings, and a file is rated mostly on complexity with the A/B line near 50. So
what moves it is splitting a file that does two jobs into two files that each do
one — chasing individual smells inside a file does almost nothing, and adding
methods to a file only adds cost. Flog also multiplies nested blocks, so a block
inside a block costs far more than the same work side by side. Worth knowing
before rewriting anything to satisfy the gate.

**One HTTP client, one set of manners** — `Http::Client` is the only code in
the project that touches `Net::HTTP`. It owns the retry, the pacing between
requests, the request logging, and `BROWSER`, the User-Agent and
Accept-Language that both scraped endpoints demand. `bin/diagnose.rb` and
`bin/capture_fixtures.rb` go through it too, so a probe cannot accidentally ask
in a way the service never would.

**Rendering is separate from orchestrating** — `WeeklyNotifier` talks to the
providers, decides which screenings survive, and enriches each film;
`Digest::Renderer` turns the result into text and asks nobody anything. The
renderer is a pure function of its input, so the digest can be reasoned about
without a single stub, and the notifier is free of every string of markup.
`CinemaListing` is what passes between them: one venue's week, already
enriched. Every split in this section left the test suite untouched, which is
the point of asserting on what the digest says rather than on how it is
assembled — it is what makes the next refactor cheap.

**The timezone is configuration, and tzinfo owns the rules** — a service about
cinemas in Gijón should not change its mind about what day it is depending on
where the process runs, so `Clock` answers rather than `Date.today`. The zone
lives in `config/cinemas.yml` beside the cinemas it describes, because pointing
this at another city should be one file and not a code change; a config without
it still runs, on the city the service was written for. Setting `TZ` on the
workflow would have been one line and no dependency, but it fixes only the
runner — a local run, or a second workflow someone adds later, would be wrong
again and silently. tzinfo is a fourth dependency bought deliberately: hand-rolling
"last Sunday in March" is correct only until the EU changes the rule.

**Reconciling the providers is its own object** — `Reconciliation` takes the
weeks the providers answered with and reads them as one, deciding which records
describe the same film and which claims about a screening to believe. It went
into a class of its own when the matching stopped being a `group_by` one-liner:
the rules have real evidence behind them and want somewhere to be explained,
and the notifier's job is to ask the providers and hand the answer on, not to
adjudicate between them. It is pure, and independent of the order the providers
were given in — but only because it sorts the records at a minute before
grouping them, which is load-bearing rather than tidiness: see *Being the same
film is not transitive* below. `Film#same_film_as?` is the one piece that lives
elsewhere: whether two records are the same film is the film's own business.

**`Film` is a mutable PORO** — `title` starts `nil` and is filled after TMDB lookup. `Data.define` was rejected here because immutability would require propagating new instances across all `ScreeningSession` references that already hold the original `Film`.

**`ScreeningSession` is `Data.define`** — fully resolved at construction time, never mutated.

**`original_version?` resolved by the reader** — `VO_BUCKETS.include?(bucket)` lives in `Sensacine::Day`, and the `VO_LANGUAGES` tags in `Yelmo::Listing`. Domain objects stay free of provider-specific string vocabulary (`"original"`, `"local"`, `"dubbed"`).

**A provider never filters, it only reports** — `sessions_for(cinema, date)` returns every session it found with `original_version?` already set, and `WeeklyNotifier#surviving` is what drops the dubbed ones when the venue's `check_vo` says to. That keeps each provider a pure data source and puts the one policy decision in one place.

**Spanish-original films fall back to a TMDB check** — a Spanish production is never dubbed or subtitled, so no provider ever marks its plain screening as VO; its only version simply *is* the original one. When `check_vo` would otherwise drop a session, `WeeklyNotifier#surviving` asks `Movies::Tmdb#spanish_original?(film)` before excluding it, and keeps the session if TMDB's `original_language` is `"es"`. The repeated asking costs nothing: `Movies::Tmdb` caches its own searches, so the notifier keeps no lookup table of its own.

**`Rating` is a NullObject** — `Rating.null` returns a frozen instance with `score: nil`. Both present and null ratings implement `to_s` / `to_str`, so callers push them into a parts array and call `.join(" ").strip` — no conditionals, no `nil` checks. `Rating.null.to_s` returns `""`, which `strip` absorbs silently. `to_str` enables implicit coercion in `String#+` and `Array#join`.

**Command-query separation on `Movies::Tmdb`** — `fetch_original_title`, `rating_for` and `spanish_original?` are pure queries. Mutation (`film.title =`) stays in `WeeklyNotifier`, which owns the enrichment lifecycle.

**Unified constructor signatures** — every provider, movie database and messenger shares the same call site: plain `.new`, with collaborators and secrets as defaulted keyword arguments. `Messengers::Stdout`, which needs no config at all, declares `def initialize(**) = nil` to accept and discard any kwargs, so a caller passing options uniformly does not have to special-case it.

**`DOMAIN` constant per class** — base URL extracted to the top of each file. Renaming a service is a single-line edit, and derived strings (headers, paths) reference `DOMAIN` via interpolation so they update automatically.

**`Http::Client` is a collaborator, not a superclass or a mixin** — every class that talks to a service takes one as `http:` and defaults it to a fresh instance with its own `HEADERS`. Inheritance and a mixin were both rejected: this way the network is injectable for tests without any of them naming a method the project owns, and `bin/` can build one directly. GET and POST differ only in the request they build, so they hand a block to one `with_one_retry`: attempt, pause, and on anything but a 200 attempt once more behind a much longer pause. The block builds a fresh request each time — a `Net::HTTP` request that has been on the wire once is not safe to send again.

**A film is compared across providers by `Film#same_film_as?`** — see *Matching a film across providers* below for the rule and the evidence behind it. Note that `Film#==` is different and stricter: it counts the year, so `Nosferatu` 1922 and 2024 stay two films, and it is what `films.uniq` and the ratings hash use once a week has already been reconciled.

**`WeeklyNotifier` uses generic dependency names** — `showtimes:`, `movies_db:`, `messenger:` rather than `sensacine:`, `tmdb:`, `telegram:`. Any conforming implementation (e.g. `Messengers::Stdout`, a future non-TMDB movie database) plugs in without changing the orchestrator.

## Matching a film across providers

Ocimax is described by both SensaCine and Yelmo, so the same screening arrives
twice and has to be recognised as one. `Reconciliation` groups every session by
`[date, starts_at]` — one cinema, one minute — and then asks
`Film#same_film_as?` which of them describe the same film. A multiplex runs
several screens at once, so two films starting at the same minute is ordinary
and the film has to decide.

### The rule

1. **The titles match by `Film#key`** — downcased and stripped, because the two
   providers disagree about capitals and stray spaces (`"La Odisea"` against
   `"La odisea"`, `"…La Dino película"` against `"…La dino película"`). This
   settles almost everything.
2. **Otherwise the director rescues it** — when *both* providers name a
   director, the names match once whitespace is squeezed, **and** one title is a
   prefix of the other. That is what makes SensaCine's `"Harry Potter y la
   Piedra Filosofal"` and Yelmo's `"…25 Aniversario"` one film.

Both halves of rule 2 are load-bearing. A director alone is not enough — a
director can have two films on at once — and a title that happens to extend
another is not enough either. Together they are hard to trip over by accident.

The director never *blocks* a match rule 1 already made. That matters: on a
co-directed film the two providers can each pick a different name from the
credits, and they do — SensaCine credits `Minions & Monsters` to Patrick Delage
where Yelmo credits Pierre Coffin. Both are right, and the film still merges on
its title.

Whichever record wins, the digest prints the **shortest** title, because the
records that needed rescuing differ by a marketing suffix and the name without
it is the film's real one. Ties break alphabetically, which carries no meaning
beyond settling `"La Sustancia"` against `"La sustancia"` the same way every
run — a rule with an actual opinion about capitals is still wanted.

### Being the same film is not transitive

Rule 2 can hold between A and B, and between A and C, while B and C match
neither each other nor anything else — a bare title is a prefix of two
different suffixed ones that are prefixes of neither. A record joins the group
whose *first* member it matches, so whichever record is read first anchors the
group and decides what merges with what.

`Reconciliation#one_per_film` therefore **sorts the records at a minute by
`spelling_rank` before grouping them**. That is what makes the answer a function
of the records rather than of the order the providers were asked in, and it is
why the shortest title anchors each group. Remove the sort and the same week can
merge two ways on two runs;
`test_three_spellings_at_one_minute_group_the_same_way_whatever_the_order`
pins it.

Grouping by connected components instead — merge A, B and C because A matches
both — was considered and is **wrong**: it would make `"Nosferatu"` swallow both
the 1922 and the 2024 film. Non-transitivity is a real property of the rule, not
an artefact to be closed over. It cannot bite on today's two providers, which
give at most two records per screening, but it is exactly what a third would
bring, so it wants a settled reading order before then rather than after.

### What the evidence says

Two runs of `bin/probe_identity.rb` against the live providers, 30–31 August
2026. Re-run it (the **Capture API fixtures** workflow, `provider=identity`)
before changing any of this.

- **A title cannot be repaired through TMDB.** `"Harry Potter y la Piedra
  Filosofal 25 Aniversario"` and `"The Fast & The Furious 25 aniversario"` both
  return **no results at all**. Worse, the one edition-suffixed title TMDB did
  answer it answered wrongly: SensaCine's `"The Fast and the Furious (A todo
  gas) - 25 Aniversario"` resolved to **`"Fast & Furious X"` (2023)**, past a
  `year=2026` filter. Canonicalising on that id would have renamed the film in
  the digest and merged it with the wrong one.
- **TMDB adds nothing where it does work.** 15 films resolved to the same id
  from both providers — and every one of those pairs differed only in capitals,
  which `key` already handles. So the expensive option buys nothing the cheap
  one does not.
- **Neither provider publishes an id the other would recognise.** SensaCine
  carries Allociné ids (`internalId`, plus a base64 `id`); Yelmo carries its own
  `Id`, a slug `Key` and a Vista `VistaId`.
- **The director is published by both, and agrees.** 11 of 12 comparable films
  matched once whitespace was squeezed; the 12th was the co-director case above.
  Yelmo pads some names with a double space (`"Will␣␣Gluck"`), which is why the
  comparison squeezes rather than compares as written.
- **What it buys, measured:** 9 screenings in that week at Ocimax failed to
  group. 8 were Harry Potter, which the rule now fixes. The 9th was a concert
  SensaCine listed with no title and no credits — nothing can match that, and
  nothing should try.

### Where to take it next

In rough order of value for effort. Before changing any of it: predict what the
change does to `by_director` and `unmatched` in the agreement block, then check
against the baseline in *Reading the agreement block* below. Loosening the rule
also makes non-transitivity easier to hit, and the sort only settles *which* way
that resolves, not whether the resolution is right.

- **Normalise punctuation before the prefix test.** The prefix test misses
  `"The Fast and the Furious (A todo gas) - 25 Aniversario"` against `"The Fast
  & The Furious 25 aniversario"` — `and` against `&`, plus a parenthetical.
  Folding conjunctions, punctuation and accents would catch it. Brittle, so it
  wants the disagreement counter first.
- **A suffix vocabulary** (`25 Aniversario`, `Re-estreno`, `4K`, `VOSE`) stripped
  before comparison would make the prefix test unnecessary rather than extending
  it, and would fix the spelling that prints as a side effect. It needs a real
  sample of suffixes to be worth writing; the probe collects one.
- **SensaCine's `originalTitle`** is in the payload and currently unread. It may
  make a TMDB request per film unnecessary, and it is a second cross-provider
  signal — but Yelmo's `OriginalTitle` is empty, so on today's two providers it
  can only help the TMDB search, not the matching.
- **Runtime, not just an hour** — the ceiling on all of this is that
  `[date, starts_at]` assumes two providers agree to the minute. They do today.
  A provider that rounded, or listed a different screen's time, would break
  every rule above; `RunTime`/`runtime` are published by both and would let a
  looser time window stay safe.

## Reading the agreement block

With the union rule a provider that quietly stops tagging VO is invisible: the
others carry, and the digest just gets thinner — indistinguishable from a quiet
week. Ocimax is described by two independent providers, so the rate at which
they contradict each other is a free drift detector. Every run prints one:

```
===== BEGIN agreement =====
run_on,cinema,overlapping,disagreed,sole_vo_source,by_title,by_director,unmatched
2026-09-01,Yelmo Cines Ocimax Gijón,117,7,Yelmo,111,6,6
===== END agreement =====
```

**That row is measured, not illustrative** — taken on 1 September 2026 with
`bin/preview.rb` through the **Weekly VO Cinema Notifier** workflow
(`dry_run: true`). Take the reading again the same way; it prints the digest
too, and cannot post.

- `overlapping` — screenings more than one provider described. Only these can
  be disagreed about, so they are the denominator; a venue with one provider
  gets no row at all, because one voice cannot be contradicted.
- `disagreed` / `sole_vo_source` — how often they differed on
  `original_version?`, and who was the lone voice for it.
- `by_title` / `by_director` / `unmatched` — which rule merged each screening,
  and how many records found no partner at a minute both providers reported on.
  This is what makes the matching rules safe to loosen: a change that makes
  `by_director` jump is visible instead of silent.

**Disagreement is the healthy state here.** SensaCine files Yelmo's subtitled
prints as dubbed, so Yelmo is routinely the only one calling a screening
original version. What is worth alarming on is `disagreed` at zero over a
non-zero `overlapping`, `sole_vo_source` emptying, or `overlapping` at zero
with `unmatched` high — that last one means both providers are talking and
nothing they say lines up.

**What the one reading we have looks like**, as a reference point rather than a
distribution — it is a single week at a single cinema:

- `disagreed` / `overlapping` — **7/117, about 6%**. Yelmo was the lone VO voice
  every time.
- `by_director` / merges — **6/117, about 5%**. Small, and exactly the
  population the rescue was built for: the anniversary Harry Potter and the
  concert SensaCine lists untitled. Before the rescue those printed under
  Yelmo's suffixed spelling with no rating, because TMDB cannot find
  `"…25 Aniversario"`; merged, they take SensaCine's clean name and resolve.
- `by_title` + `by_director` came to exactly `overlapping`, which holds only
  while every merge is two records from two providers. A third provider, or one
  listing a film twice at a minute, would separate them.

A caveat on reading the ratio too closely: `disagreed` counts merges the VO
filter later dropped as well as the ones that reached the digest, so it is not
the number of subtitled screenings a subscriber saw.

It goes in the run log and never in the Telegram digest: provider health is not
something a subscriber should have to read about.

**Nothing is persisted, deliberately.** The service is a stateless Actions cron,
and GitHub keeps the logs 90 days — about 26 runs of history for free. The
signals above are absolute rather than relative, so a single run is readable
without a baseline. If watching the trend ever needs more, the rows are already
valid CSV between markers: appending them to a file becomes a change to
`weekly.yml` (`sed -n '/BEGIN agreement/,/END agreement/p'` after `bin/run.rb`)
with no change to any code. `actions/cache` would be the wrong home — it evicts
after 7 days of no access, and a health monitor that silently loses its baseline
is worse than none.

## Does the programme fill in mid-week?

An open question, recorded with its evidence and a prediction, because the
answer changes what the baseline above means.

The 1 September reading looks like a quiet week at Ocimax: bookable screenings
on four of seven days. The likelier reading is that the cinemas publish a base
programme and put the rest on sale later, closer to the weekend — in which case
`overlapping` measures how much was **on sale when we asked**, not how much is
on, and the Monday digest systematically under-reports the coming weekend.

Two readings taken two days apart say exactly the same thing:

| Asked on | Data through | First empty day | `nextDate` |
|---|---|---|---|
| 30 Aug (identity probe, run 33325096167) | Fri 4 Sep | Sat 5 Sep | **Thu 10 Sep** |
| 1 Sep (preview, run 33449170994) | Fri 4 Sep | Sat 5 Sep | **Thu 10 Sep** |

A multiplex with no Saturday programme is not credible, so those empty days are
almost certainly "not on sale yet" rather than "nothing on". `nextDate` naming a
**Thursday** fits the Spanish release cycle, where the programme turns over
Thursday or Friday.

**The boundary did not move in those two days**, so it is not a gradual fill. If
it fills, it happens at a moment — which is what makes a mid-week reading a test
rather than another data point.

**The prediction, written before the test:** the Tuesday 1 September reading
still shows *data through 4 Sep, next 10 Sep* (the control — it should match the
two above), and the Wednesday 2 September one shows the window extending past
Friday 4 Sep. If Wednesday still reads *through 4 Sep, next 10 Sep*, the theory
is wrong as stated — either the week is genuinely thin, or the fill happens
later or on another cadence. Recording the prediction first is what stops the
result being rationalised afterwards; the `overlapping` guess for the baseline
came out an order of magnitude low, and that was only visible because it had
been written down.

**Programme watch** takes the readings: a dry run at noon on Tuesday and in the
morning on Wednesday and Saturday. Tuesday is the "before" point, taken while
the window is known to end on the Friday; Wednesday brackets the moment the
fill is suspected to happen; Saturday says whether it kept moving. Compare, for
theatre `E0628`, which dates return screenings and which return
`next.showtime.on` with what `nextDate`; the dates to watch first are **5–9
September**. It carries no Telegram secrets and so cannot post.

That workflow is **temporary** — it exists to settle this question, and should
be deleted once the answer is written down here. Reading it by eye is the whole
method; nothing is persisted, for the same reasons as the agreement block.

If it is confirmed, two things follow. `Digest::Renderer#closing_notes` says
*"Nothing left to catch this week at: …"*, which for a venue whose programme is
merely unpublished is the same class of wording error as calling a drained day
empty — it implies the screenings have been and gone. And a `programme` block
beside the agreement one — per cinema, how many of the seven days carry a
session, and the `nextDate` named when they do not — would make the fill visible
run over run at no extra request cost.

## Known gaps

Recorded rather than fixed, with enough context to pick up cold.

**The end-to-end fixtures never exercise a cross-provider merge.** SensaCine's
Ocimax fixture and Yelmo's cover different days, so `end_to_end_test.rb` has no
screening both providers describe: the digest is byte-identical with and
without the matching rules, and the agreement row it prints is all zeroes. The
merge and agreement tests cover the behaviour directly, but a refreshed capture
that overlapped would make the end-to-end test carry it too.
