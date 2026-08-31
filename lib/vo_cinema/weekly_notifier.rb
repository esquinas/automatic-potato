# frozen_string_literal: true

require "date"

module VoCinema
  # The orchestrator: ask every provider about every cinema, read their accounts
  # as one, log how much they agreed, and send what is left to read.
  #
  # It takes a list of showtimes providers; a provider that does not cover a
  # venue says so by answering with nothing. The order they are given in does
  # not matter — Reconciliation unions their claims rather than letting the last
  # one win.
  #
  # What survives the week and what it reads like are Digest::Programme's and
  # Digest::Renderer's; what stays here is the part that talks to other things.
  class WeeklyNotifier
    WEEK_DAYS = 7

    def initialize(showtimes:, movies_db:, messenger:, cinemas:)
      @showtimes = Array(showtimes)
      @movies_db = movies_db
      @messenger = messenger
      @cinemas   = cinemas
    end

    def run(today: Date.today)
      weeks = @cinemas.map { |cinema| [cinema, Reconciliation.new(week_from_every_provider(cinema, today))] }

      report_agreement(weeks, today)
      deliver(digest_of(Digest::Programme.new(weeks, movies_db: @movies_db), today))
    end

    private

    # Every provider is asked about every cinema, and answers for itself. Its
    # name comes along so the agreement report can say which of them said what.
    def week_from_every_provider(cinema, today)
      @showtimes.map { |provider| [provider.name, seven_days_from(provider, cinema, today)] }
    end

    def seven_days_from(provider, cinema, today)
      WEEK_DAYS.times.flat_map { |offset| provider.sessions_for(cinema, (today + offset).to_s) }
    end

    def digest_of(programme, today)
      Digest::Renderer.new(today: today, week_days: WEEK_DAYS)
                      .render(programme.listings, programme.venues_with_nothing_left)
    end

    def deliver(message)
      @messenger.send_message(message)
      puts "Sent #{message.length} chars"
    end

    # Provider health goes in the run log and never in the digest. Silent when
    # no venue had two providers to compare — that is not a finding.
    def report_agreement(weeks, today)
      health = AgreementReport.new(weeks.map { |cinema, week| [cinema, week.agreement] }, today).to_s

      puts health unless health.empty?
    end
  end
end
