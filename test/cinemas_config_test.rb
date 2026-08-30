# frozen_string_literal: true

# config/cinemas.yml is the one file a user is expected to edit, and a typo in
# it fails quietly: a wrong theatre id just looks like a quiet week.
#
# Cinema.all is what turns those entries into objects, so these read the real
# file through it — a key renamed in one place and not the other shows up here
# rather than in a Monday digest.
class CinemasConfigTest < ServiceTest
  CINEMAS = Cinema.all

  def test_gijons_cinemas_are_configured
    assert_operator CINEMAS.length, :>=, 1
  end

  def test_every_cinema_has_a_name_to_print
    CINEMAS.each { |cinema| refute_empty cinema.name.to_s, "a cinema is missing its name" }
  end

  def test_every_cinema_is_identified_to_at_least_one_provider
    # A venue no provider can name has nothing to report, whatever else the
    # entry says about it.
    CINEMAS.each do |cinema|
      assert cinema.sensacine_id || cinema.yelmo_id, "#{cinema.name} is identified to no provider"
    end
  end

  def test_no_cinema_is_configured_twice
    ids = CINEMAS.filter_map(&:sensacine_id)

    assert_equal ids.uniq, ids, "the same SensaCine id is listed more than once"
  end

  def test_every_link_is_a_link
    CINEMAS.filter_map(&:url).each { |url| assert_match %r{\Ahttps://}, url }
  end

  def test_the_vo_filter_is_switched_on_or_left_off_and_never_set_to_something_else
    # WeeklyNotifier tests this for truthiness, so a stray "no" would read as
    # "yes" and silently empty a venue's section.
    CINEMAS.each do |cinema|
      assert_includes [true, false], cinema.check_vo, "#{cinema.name} has check_vo: #{cinema.check_vo.inspect}"
    end
  end

  def test_a_yelmo_id_names_a_city_and_a_cinema_within_it
    # Showtimes::Yelmo splits this on the first slash: the city is what it asks
    # for, the cinema is what it looks for in the answer.
    CINEMAS.filter_map(&:yelmo_id).each do |yelmo_id|
      city, cinema_key = yelmo_id.split("/", 2)

      refute_empty city.to_s, "#{yelmo_id.inspect} has no city"
      refute_empty cinema_key.to_s, "#{yelmo_id.inspect} has no cinema"
    end
  end

  def test_only_cinemas_that_are_filtered_need_a_second_opinion_from_yelmo
    # A yelmo_id exists to rescue original-version screenings from a filter. On
    # a venue that is not filtered it would have nothing to do.
    CINEMAS.select(&:yelmo_id).each do |cinema|
      assert cinema.check_vo, "#{cinema.name} has a yelmo_id but is not filtered"
    end
  end
end
