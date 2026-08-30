# frozen_string_literal: true

require "json"

# The last step: hand the finished digest to the Telegram Bot API.
class TelegramTest < ServiceTest
  # What Telegram sends back when a message goes out.
  DELIVERED = JSON.generate(
    "ok" => true,
    "result" => {
      "message_id" => 4127,
      "from" => { "id" => 7_842_115_903, "is_bot" => true,
                  "first_name" => "Gijón VO Cinema", "username" => "esquinas_gijon_vo_cinema_bot" },
      "chat" => { "id" => -1_001_234_567_890, "title" => "Cine VO Gijón", "type" => "channel" },
      "date" => 1_787_873_200,
      "text" => "Yelmo Cines Ocimax Gijón"
    }
  )

  def setup
    @http = FakeHttp.new
    @http.answers "api.telegram.org", body: DELIVERED
  end

  def deliver(text, token: "7842115903:AAH2-fake-token-for-tests", chat_id: "-1001234567890")
    @http.while_intercepting { Messengers::Telegram.new(token: token, chat_id: chat_id).send_message(text) }
  end

  def test_the_digest_is_posted_to_the_bot_s_own_send_message_endpoint
    deliver("<b>Yelmo Cines Ocimax Gijón</b>")
    request = @http.requests.first

    assert_equal "POST", request.verb
    assert_equal "https://api.telegram.org/bot7842115903:AAH2-fake-token-for-tests/sendMessage",
                 request.url
  end

  def test_the_digest_goes_to_the_configured_chat
    deliver("<b>Yelmo Cines Ocimax Gijón</b>", chat_id: "-1009998887776")
    payload = JSON.parse(@http.requests.first.body)

    assert_equal "-1009998887776", payload["chat_id"]
  end

  def test_the_digest_is_sent_as_html_because_that_is_what_it_is_written_in
    # The notifier formats films with <b>, original titles with <i> and
    # showtimes inside <pre> so the times line up in a monospaced block.
    deliver("<b>La sustancia</b> <i>(The Substance)</i> ★ 7.1\n<pre>• Vie → 19:30</pre>")
    payload = JSON.parse(@http.requests.first.body)

    assert_equal "HTML", payload["parse_mode"]
    assert_includes payload["text"], "<pre>"
    assert_includes payload["text"], "★ 7.1"
  end

  def test_accents_survive_the_trip
    # Nearly every title in this digest carries one.
    deliver("Tadeo Jones y la lámpara maravillosa — Gijón")
    payload = JSON.parse(@http.requests.first.body)

    assert_equal "Tadeo Jones y la lámpara maravillosa — Gijón", payload["text"]
  end

  def test_a_digest_too_long_for_telegram_is_cut_short_rather_than_rejected
    # Telegram refuses anything over 4096 characters outright, which would cost
    # the whole digest instead of its tail. Better most of the week than none.
    week_at_a_busy_arthouse = (1..60).map do |n|
      "<b>Película número #{n} del ciclo de verano</b>\n<pre>• Fri → 19:30, 21:00</pre>"
    end.join("\n\n")

    deliver(week_at_a_busy_arthouse)
    delivered = JSON.parse(@http.requests.first.body)["text"]

    assert_operator week_at_a_busy_arthouse.length, :>, 4096, "the digest under test has to be an oversized one"
    assert_operator delivered.length, :<, 4096
    assert_includes delivered, "truncated"
    assert_includes delivered, "Película número 1 del ciclo de verano"
  end

  def test_a_digest_telegram_will_accept_is_sent_untouched
    whole_week = "<b>Yelmo Cines Ocimax Gijón</b>\n<pre>• Sat → 19:30</pre>"

    deliver(whole_week)

    assert_equal whole_week, JSON.parse(@http.requests.first.body)["text"]
  end

  def test_it_reads_its_credentials_from_the_environment_by_default
    # bin/run.rb builds it with a bare .new; GitHub Actions supplies the
    # secrets.
    previous = ENV.to_h.slice("TELEGRAM_BOT_TOKEN", "TELEGRAM_CHAT_ID")
    ENV["TELEGRAM_BOT_TOKEN"] = "token-from-the-environment"
    ENV["TELEGRAM_CHAT_ID"]   = "-1005554443332"

    @http.while_intercepting { Messengers::Telegram.new.send_message("hola") }
    payload = JSON.parse(@http.requests.first.body)

    assert_includes @http.requests.first.url, "bottoken-from-the-environment/"
    assert_equal "-1005554443332", payload["chat_id"]
  ensure
    %w[TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID].each do |name|
      previous.key?(name) ? ENV[name] = previous[name] : ENV.delete(name)
    end
  end
end
