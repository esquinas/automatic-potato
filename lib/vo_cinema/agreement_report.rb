# frozen_string_literal: true

require "csv"

module VoCinema
  # The provider health block as it appears in the run log.
  #
  # It goes in the log and never in the digest: a subscriber should not have to
  # read about which API changed shape.
  #
  # The rows are valid CSV between markers, in the style bin/capture_fixtures.rb
  # already uses, so that persisting them later — appending them to a file each
  # run to watch the trend — is a change to the workflow rather than to any of
  # this code. The columns stay fixed as the provider list changes: which
  # provider was the lone voice for a screening is a value, not a column.
  class AgreementReport
    COLUMNS = %w[
      run_on cinema overlapping disagreed sole_vo_source by_title by_director unmatched
    ].freeze

    BEGINNING = "===== BEGIN agreement ====="
    ENDING    = "===== END agreement ====="

    def initialize(agreements, today)
      @agreements = agreements
      @today      = today
    end

    # Empty when no venue had two providers to compare, which is not a finding
    # and should print nothing at all.
    def to_s
      return "" if rows.empty?

      [BEGINNING, CSV.generate_line(COLUMNS).chomp, *rows, ENDING].join("\n")
    end

    private

    def rows = @agreements.filter_map { |cinema, agreement| row_for(cinema, agreement) }

    # A venue only one provider covers has no health signal to give, and a row
    # of zeroes would read as a finding rather than as silence. Anywhere two
    # providers both spoke gets a row even when nothing matched — especially
    # then, since that is the loudest thing this report can say.
    def row_for(cinema, agreement)
      return nil unless agreement.comparable?

      CSV.generate_line([@today, cinema.name, agreement.overlapping, agreement.disagreed,
                         agreement.sole_vo_source.join(";"), agreement.by_title,
                         agreement.by_director, agreement.unmatched]).chomp
    end
  end
end
