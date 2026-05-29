# Gijón VO Cinema Weekly Notifier — Plan

## Purpose

A Ruby script that queries SensaCine’s internal JSON API weekly for non-dubbed movie screenings in Gijón, enriches results with TMDB ratings, and delivers a Telegram digest every Monday morning. Cinemas are configured via YAML.

---

## Architecture

### Components

| File | Role |
|---|---|
| `config/cinemas.yml` | User-editable list of cinemas (name + SensaCine ID) |
| `lib/scraper.rb` | Query SensaCine internal JSON API + parse results |
| `lib/tmdb_client.rb` | Enrich film titles with TMDB ratings |
| `lib/notifier.rb` | Format and send Telegram message |
| `bin/run.rb` | Entry point — orchestrates all steps |
| `.github/workflows/weekly.yml` | Monday 08:00 UTC cron trigger |
| `Gemfile` | Ruby dependencies |
| `.env.example` | Document required env vars |

### Gems

| Gem | Purpose |
|---|---|
| `httparty` | HTTP client for SensaCine JSON API + TMDB |
| `dotenv` | Load `.env` in local development |

Nokogiri is **not needed** — the SensaCine internal JSON API returns structured data directly.

### Secrets (GitHub Actions)

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_CHAT_ID`
- `TMDB_API_KEY`

---

## Data Source: SensaCine Internal JSON API (Verified)

SensaCine (owned by the same Webedia group as AlloCiné, France) exposes an internal JSON API used by its own frontend. This endpoint is **confirmed working** by multiple open-source scrapers (lefevre-dev/AllocineAPI, 2023):

```
GET https://www.sensacine.com/_/showtimes/theater-{ID}/d-{DATE}/p-{PAGE}/
```

- `{ID}` — SensaCine theater code, e.g. `E0628` (Yelmo Ocimax Gijón)
- `{DATE}` — `YYYY-MM-DD` format
- `{PAGE}` — integer, starting at 1

**Response structure:**
```json
{
  "pagination": { "page": 1, "totalPages": 2 },
  "results": [
    {
      "movie": { "title": "Anora" },
      "showtimes": {
        "original": [
          { "internalId": "...", "startsAt": "2026-06-02T20:45:00", "diffusionVersion": "VO" }
        ],
        "dubbed": [
          { "internalId": "...", "startsAt": "2026-06-02T18:00:00", "diffusionVersion": "VF" }
        ],
        "local": []
      }
    }
  ]
}
```

The API **pre-separates** sessions by `original`, `dubbed`, and `local` keys — no text-based filtering needed for the core case.

The older `api.sensacine.com/rest/v3/showtimelist` endpoint is blocked (403) since ~2021. Do not use it.

---

## Data Flow

```
For each cinema in config/cinemas.yml:
  GET /_/showtimes/theater-{ID}/d-{DATE}/p-{page}/ (paginated, Mon–Sun)
  → take only showtimes["original"] and showtimes["local"] keys
  → also include showtimes["dubbed"] entries if diffusionVersion is not VF/VD
    (catches Spanish films labelled under "dubbed" bucket with original Spanish audio)
  → collect: film title, diffusionVersion label, startsAt timestamps
  → for each unique film: search TMDB by title + year for rating
  → format Telegram message (chunked at 3500 chars if needed)
  → POST to Telegram Bot API
```

---

## Cinema Config (`config/cinemas.yml`)

```yaml
cinemas:
  - name: Yelmo Cines Ocimax
    sensacine_id: E0628
```

Adding a cinema = one new entry. The SensaCine ID is the code in the cinema’s URL: `sensacine.com/cines/cine/{ID}/`.

---

## VO Filter Logic

The JSON API already does most of the work via the `original`/`dubbed`/`local` keys. However the `local` bucket and edge cases (Spanish films, Basque/Galician films in their own language) need a secondary check on `diffusionVersion`:

**Exclude** any session where `diffusionVersion` matches:
```ruby
DUBBED_PATTERN = /\A(VF|VD)\z/i
```

**Include** everything else: `VO`, `VOSE`, `VOS`, `V.O.S.E.`, `VOSI`, blank/nil (flagged with `·`), and any Spanish-language label.

Spanish films are included naturally — they live in the `local` or `original` bucket and their `diffusionVersion` will not be `VF`/`VD`.

---

## TMDB Matching Strategy (layered)

### Layer 1 — Search by Spanish title + year (primary)
The SensaCine JSON response gives the Spanish display title. TMDB’s search index includes **alternative titles by country**, so `GET /search/movie?query=título&primary_release_year=year` will find most films correctly, including Spanish-titled entries.

### Layer 2 — Search by title only (year fallback)
If no result with year match, retry without `primary_release_year`. Useful for films whose TMDB year differs from Spanish release year.

### Layer 3 — Ambiguity tiebreaker
If top two TMDB results have popularity within 2× of each other, skip the rating and log a warning rather than attach the wrong one.

### No cache in MVP
At ~10 films/week the TMDB free tier (50 req/s) handles this trivially. Caching is premature — omitted.

---

## Telegram Notification Format

```
🎬 VO/VOSE en Gijón — semana del 2 al 8 jun

Yelmo Cines Ocimax
──────────────────
• Anora (2024) ★ 8.0
  VO | lun 20:45, jue 20:45

• Nosferatu (2024) ★ 7.1
  VOSE | lun 20:00, mié 18:30, vie 21:00

• El 47 (2024) ★ 6.8
  · | mar 19:00

──────────────────
3 películas · 8 pases esta semana
```

- `★` rating from TMDB (omitted if ambiguous match)
- `·` format label = session had no `diffusionVersion` value (included but flagged)
- Message split into multiple if > 3500 chars

---

## GitHub Actions Schedule

```yaml
on:
  schedule:
    - cron: '0 8 * * 1'   # Mondays 08:00 UTC = 09:00/10:00 Spain local time
  workflow_dispatch:        # Manual trigger for testing
```

**Known limitation:** Free-tier cron can be delayed during high-load periods. Acceptable for personal use.

---

## Known Gotchas and Mitigations

### 1. SensaCine internal API may require session cookies or Referer header
The `/_/showtimes/` endpoint is a frontend XHR call. Requests without the right headers may get 403.
- **Mitigation:** send `Referer: https://www.sensacine.com/cines/cine/{ID}/` and a realistic `User-Agent` + `Accept: application/json`
- **If still 403 from GitHub Actions:** test with `workflow_dispatch` first; if cloud IPs are blocked, fall back to running on a VPS/home machine with cron

### 2. Pagination
The API paginates. Each page returns `pagination.totalPages`; must loop until all pages consumed.

### 3. Date window scope
The API accepts any specific date. To cover the full upcoming week (Mon–Sun), make 7 requests per cinema (one per day) and deduplicate.

### 4. `local` bucket semantics
The `local` key’s meaning is not fully documented. Likely covers regional-language versions (Catalan, Basque). Treat the same as `original` — include unless `diffusionVersion` is `VF`/`VD`.

### 5. TMDB title ambiguity
- Common or short titles may match multiple films.
- Rule: skip rating if top-2 popularity ratio < 2×.

### 6. Telegram 4096-char limit
- Chunk output at 3500 chars per message.

### 7. Timezone
- Cron in UTC; Spain is UTC+1/+2. Delivery at ~09:00–10:00 local. No action needed.

---

## Verification Status

| Check | Status | Notes |
|---|---|---|
| SensaCine `/_/showtimes/` JSON endpoint structure | ✅ Confirmed | lefevre-dev/AllocineAPI (2023); shared AlloCiné/SensaCine codebase |
| JS rendering required? | ✅ No | Endpoint returns JSON directly; no headless browser needed |
| Nokogiri needed? | ✅ No | Dropped from dependencies |
| Old `api.sensacine.com/rest/v3` | ✅ Dead | 403 since ~2021; do not use |
| Yelmo own API | ✅ None found | SensaCine is the right aggregator |
| Ocine/cinesocine API | ✅ None found | Use SensaCine IDs when adding those cinemas |
| Live endpoint reachability from GitHub Actions | ⏳ Pending | Test with first `workflow_dispatch` run |
| TMDB search accuracy for Spanish titles | ⏳ Pending | Test with a known film list |

---

## Out of Scope (MVP)

- Multiple cinemas (add more YAML entries when ready)
- Genre or rating-threshold filters
- Filmaffinity ratings (no public API)
- Persistent TMDB cache
- Web UI or dashboard
