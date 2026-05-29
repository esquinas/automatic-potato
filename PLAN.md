# Gijón VO Cinema Weekly Notifier — Implementation Plan

## Iterations

### Iteration 1 — Telegram ping
- `bin/run.rb` sends "Hello from Gijón VO bot" to Telegram
- `.github/workflows/weekly.yml` with `workflow_dispatch` + Monday 08:00 UTC cron
- Secrets required: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`
- ✅ Done when: manual trigger delivers the message to your phone

### Iteration 2 — Raw SensaCine dump
- Fetch today's showtimes for Yelmo Ocimax (page 1 only)
- Send the raw JSON (truncated to Telegram's limit) as a code block
- ✅ Done when: you can read film titles and bucket keys in Telegram

### Iteration 3 — Readable showtime list
- Parse the JSON, extract film title + session times from all three buckets
- Send a plain human-readable list (no filtering yet)
- ✅ Done when: you see "Anora — 20:45, 18:00" etc. in Telegram

### Iteration 4 — VO filter
- Keep only `original` and `local` buckets
- Add `config/cinemas.yml` as the cinema source
- ✅ Done when: dubbed-only films disappear from the message

### Iteration 5 — Full week
- Loop Mon–Sun (7 requests per cinema), deduplicate screenings
- Group times by film across the week
- ✅ Done when: message shows all 7 days' worth of VO sessions

### Iteration 6 — TMDB ratings
- Add `Gemfile` with `httparty`
- For each film, search TMDB by title + year, attach `★ X.X`
- Skip rating if ambiguous (ratio < 2×)
- ✅ Done when: ratings appear next to film titles

### Iteration 7 — Polished format
- Final Telegram format (header, cinema separator, session counts)
- Chunk messages at 3500 chars if needed
- ✅ Done when: output matches the format spec in `RESEARCH.md`

---

See `RESEARCH.md` for full architecture, API details, and verification findings.
