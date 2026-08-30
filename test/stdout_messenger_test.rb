# frozen_string_literal: true

require_relative "../lib/stdout_messenger"

# The messenger used when developing locally: it shows the digest instead of
# posting it to the real Telegram channel.
class StdoutMessengerTest < ServiceTest
  def test_it_prints_the_digest_so_a_run_can_be_checked_without_telegram
    StdoutMessenger.new.send_message("<b>Yelmo Cines Ocimax Gijón</b>\n• Sat → 19:30")

    assert_includes printed_output, "Yelmo Cines Ocimax Gijón"
    assert_includes printed_output, "19:30"
  end

  def test_it_takes_the_telegram_markup_back_off
    # The digest is written for Telegram, so it arrives full of <b> and <pre>.
    # At a terminal those are noise between you and the showtimes.
    StdoutMessenger.new.send_message(
      "<b><a href=\"https://yelmocines.es/x\">Yelmo Cines Ocimax Gijón — 2026-08-31 → 2026-09-06</a></b>\n" \
      "<b>La sustancia</b> <i>(The Substance)</i> ★ 7.1\n<pre>• Sat → 19:30, 21:45</pre>"
    )

    assert_includes printed_output, "Yelmo Cines Ocimax Gijón — 2026-08-31 → 2026-09-06"
    assert_includes printed_output, "La sustancia (The Substance) ★ 7.1"
    assert_includes printed_output, "• Sat → 19:30, 21:45"
    refute_match(/<[^>]+>/, printed_output)
  end

  def test_it_does_not_shorten_the_digest
    # Only Telegram has a length limit; a terminal gets the whole week.
    long_week = (1..60).map { |n| "<b>Película número #{n}</b>" }.join("\n")

    StdoutMessenger.new.send_message(long_week)

    assert_includes printed_output, "Película número 60"
    refute_includes printed_output, "truncated"
  end

  def test_it_can_be_built_the_same_way_as_the_telegram_messenger
    # Every Messenger answers a plain .new, and the ones that need no
    # configuration accept and discard the keywords the others require. That
    # is what lets bin/run.rb swap one for the other without any other edit.
    messenger = StdoutMessenger.new(token: "unused", chat_id: "unused")

    messenger.send_message("hola")

    assert_includes printed_output, "hola"
  end
end
