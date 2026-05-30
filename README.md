# Gijón VO Cinema

Queries SensaCine's internal JSON API every Monday morning for original-version screenings across Gijón's cinemas, enriches each film with its TMDB rating, and delivers a formatted digest to a Telegram chat. Cinemas are configured in `config/cinemas.yml`; secrets (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `TMDB_API_KEY`) are injected via environment variables. Run locally with `ruby bin/run.rb` or let the GitHub Actions cron fire automatically at 08:00 UTC every Monday.
