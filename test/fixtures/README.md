# Fixtures

Every file here is a real response, captured from the live provider rather
than invented, so the tests exercise the shapes production actually meets.

Refresh them by running the **Capture API fixtures** workflow
(`.github/workflows/capture-fixtures.yml`, manual dispatch, with a `provider`
input to narrow it down). It prints each payload to the job log between
`===== BEGIN fixture: … =====` markers; copy the block into the matching file
here. `bin/capture_fixtures.rb` is the script it runs.

Long prose (`synopsis`, `overview`) is truncated and image blobs are dropped so
the files stay readable. Every key the production code reads is verbatim.

## sensacine/

Captured 2026-08-28 from `GET /_/showtimes/theater-{id}/d-{date}/`.

| File | What it shows |
| --- | --- |
| `ocimax_all_dubbed.json` | A normal day at Yelmo Ocimax. Every screening sits in the `dubbed` bucket — the situation that made `Showtimes::Yelmo` necessary. |
| `laboral_original_version.json` | The `original`, `original_st` and `local` buckets, plus a subtitled screening misfiled under `dubbed` and betrayed only by `diffusionVersion`. |
| `ocimax_page_1_of_2.json`, `ocimax_page_2_of_2.json` | A day SensaCine splits across two pages. Derived from `ocimax_all_dubbed.json` — the capture workflow does not print these two. |
| `nothing_left_that_day.json` | How the API says a day's screenings have already run: `error: true`, the message `next.showtime.on`, and a `nextDate`. Captured at 01:26 Madrid time asking about the previous day. It does **not** mean that day had no cinema — see the note below. |

**`error: true` means expired, not absent.** SensaCine lists only screenings
you could still buy a ticket for, so a day drains as its programme runs and is
empty once the last film has started. How much of a day you see therefore
depends on what time of day you ask.

An empty *future* day is not a fault either — most often it means "not on sale
yet", and the venues with no film programme at all answer `no.showtime.error`
every day of the week. See *An empty day means expired, not absent* in
`CLAUDE.md` for how to tell the benign cases from a real one.

Note on provenance: in the week these were captured, no cinema in Gijón had a
single showtime outside the `dubbed` buckets, so `laboral_original_version.json`
is a real entry whose showtimes were moved into the original-version buckets.
The shape — every key, every bucket name — is the API's own.

Those moved showtimes carry a null `diffusionVersion` on purpose. The client
treats a screening as original version if *either* its bucket says so *or* its
`diffusionVersion` does, and leaving the second signal out is what lets the
bucket rule be tested on its own. The one entry that does carry
`diffusionVersion: "ORIGINAL"` sits in the `dubbed` bucket, so it tests the
other rule on its own in turn.

## yelmo/

`now_playing_asturias.json` — captured 2026-08-28 from
`POST /now-playing.aspx/GetNowPlaying` with `{"cityKey":"asturias"}`. Two days
at Ocimax Gijón. Harry Potter runs twice a day there: once with
`Language: "INGLÉS SUBTITULADO EN ESPAÑOL (VOSE)"` and once dubbed into
Spanish — the pair that SensaCine reports as two identical dubbed screenings.

## tmdb/

Captured 2026-08-28 from `GET /3/search/movie`, one file per query.
`search_el_ser_querido.json` is the Spanish production whose
`original_language` is `es`; the others are English-language films with a
Spanish release title.
