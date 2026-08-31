# frozen_string_literal: true

require "date"
require "tmpdir"

# "Today" means today in Gijón, which is not the same as Date.today.
#
# Date.today reads the timezone of whatever machine is running, and a GitHub
# runner is on UTC. A run started just after midnight in Gijón therefore saw
# yesterday: it asked the providers for a day already shown, never asked about
# the last day of the week, and headed the digest with a range off by one. The
# scheduled cron fires at 11:00 local and never noticed; a manual run late in
# the evening did, on 2026-08-31.
class ClockTest < ServiceTest
  # 00:45 on 1 September in Gijón is still 31 August in UTC — the exact instant
  # the preview run went out.
  JUST_AFTER_MIDNIGHT_THERE = Time.utc(2026, 8, 31, 22, 45, 51)

  def config_saying(contents)
    dir = Dir.mktmpdir
    File.write(File.join(dir, "cinemas.yml"), contents)
    File.join(dir, "cinemas.yml")
  end

  def test_the_date_is_the_one_the_cinemas_are_living
    zone = Clock.zone(config_saying("timezone: Europe/Madrid\ncinemas: []\n"))

    assert_equal Date.new(2026, 9, 1), zone.to_local(JUST_AFTER_MIDNIGHT_THERE).to_date
  end

  def test_that_is_a_different_day_from_the_one_the_machine_thinks
    # The bug in one line: the same instant is two dates, and the service is
    # about cinemas rather than about servers.
    assert_equal Date.new(2026, 8, 31), JUST_AFTER_MIDNIGHT_THERE.to_date
  end

  def test_the_summer_and_winter_offsets_both_come_out_right
    # Gijón moves between CET and CEST, which is the reason for naming a zone
    # rather than writing an offset down: 11:00 local is 09:00 UTC in one half
    # of the year and 10:00 in the other.
    zone = Clock.zone(config_saying("timezone: Europe/Madrid\ncinemas: []\n"))

    assert_equal 2 * 3600, zone.observed_utc_offset(Time.utc(2026, 8, 31, 12))
    assert_equal 1 * 3600, zone.observed_utc_offset(Time.utc(2026, 12, 31, 12))
  end

  def test_the_zone_is_read_from_the_cinema_config
    # It belongs with the cinemas it describes: a service pointed at another
    # city changes one file.
    assert_equal "America/Mexico_City",
                 Clock.name(config_saying("timezone: America/Mexico_City\ncinemas: []\n"))
  end

  def test_a_config_with_no_timezone_still_runs
    # A missing line should not cost a Monday digest.
    assert_equal "Europe/Madrid", Clock.name(config_saying("cinemas: []\n"))
  end

  def test_the_real_config_names_a_zone_tzinfo_recognises
    # The one file a user edits, checked against the same lookup production
    # uses — a typo here would fail every run rather than one.
    assert_equal "Europe/Madrid", Clock.name
    assert_kind_of Date, Clock.today
  end
end
