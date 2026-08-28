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

  def test_it_can_be_built_the_same_way_as_the_telegram_messenger
    # Every Messenger answers a plain .new, and the ones that need no
    # configuration accept and discard the keywords the others require. That
    # is what lets bin/run.rb swap one for the other without any other edit.
    messenger = StdoutMessenger.new(token: "unused", chat_id: "unused")

    messenger.send_message("hola")

    assert_includes printed_output, "hola"
  end
end
