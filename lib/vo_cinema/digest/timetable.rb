# frozen_string_literal: true

require "date"

module VoCinema
  module Digest
    # One film's week at one cinema, laid out for reading.
    #
    # Times are grouped by day and right-aligned into a column, so the eye can run
    # straight down them; a film showing every single day collapses to a single
    # line rather than seven, which is what stops a daily blockbuster crowding out
    # the one-off screenings the digest exists for.
    #
    # Plain text, no markup: whoever prints this decides how it is dressed.
    class Timetable
      def initialize(sessions, week_days:)
        @days = sessions.group_by(&:date)
                        .transform_values { |group| group.map(&:starts_at).sort.uniq }
                        .sort.to_h
        @week_days = week_days
      end

      def to_s = whole_week? ? all_week : day_by_day

      private

      def whole_week? = @days.length == @week_days

      def all_week
        dates = @days.keys

        "• All week: #{dates.min} → #{dates.max}\n  #{aligned(every_time)}"
      end

      def day_by_day
        @days.map { |date, times| "• #{weekday(date)} → #{aligned(times)}" }.join("\n")
      end

      # Every column is as wide as the longest time in the block, so a 9:30 sits
      # under a 21:15 rather than beside it.
      def aligned(times) = times.map { |time| time.rjust(width) }.join(", ")

      def width = @width ||= every_time.map(&:length).max

      def every_time = @days.values.flatten.sort.uniq

      def weekday(date) = Date.parse(date).strftime("%a")
    end
  end
end
