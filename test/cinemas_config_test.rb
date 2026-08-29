# frozen_string_literal: true

require "yaml"

# config/cinemas.yml is the one file a user is expected to edit, and a typo in
# it fails quietly: a wrong theatre id just looks like a quiet week.
# These are the checks that turn that into a red build instead.
class CinemasConfigTest < ServiceTest
  CINEMAS = YAML.load_file(File.expand_path("../config/cinemas.yml", __dir__))["cinemas"].freeze

  def test_gijon_s_cinemas_are_configured
    assert_operator CINEMAS.length, :>=, 1
  end

  def test_every_cinema_has_a_name_to_print_and_an_id_to_look_up
    CINEMAS.each do |cinema|
      refute_empty cinema["name"].to_s, "a cinema is missing its name: #{cinema.inspect}"
      refute_empty cinema["id"].to_s, "#{cinema["name"]} is missing its SensaCine id"
    end
  end

  def test_no_cinema_is_configured_twice
    ids = CINEMAS.map { |cinema| cinema["id"] }

    assert_equal ids.uniq, ids, "the same SensaCine id is listed more than once"
  end

  def test_every_link_is_a_link
    CINEMAS.filter_map { |cinema| cinema["url"] }.each do |url|
      assert_match %r{\Ahttps://}, url
    end
  end

  def test_the_vo_filter_is_switched_on_or_left_off_and_never_set_to_something_else
    # WeeklyNotifier tests this key for truthiness, so a stray "no" would read
    # as "yes" and silently empty a venue's section.
    CINEMAS.each do |cinema|
      next unless cinema.key?("check_vo")

      assert_includes [true, false], cinema["check_vo"],
                      "#{cinema["name"]} has check_vo: #{cinema["check_vo"].inspect}"
    end
  end

  def test_a_yelmo_id_names_a_city_and_a_cinema_within_it
    # YelmoClient splits this on the first slash: the city is what it asks for,
    # the cinema is what it looks for in the answer.
    CINEMAS.filter_map { |cinema| cinema["yelmo_id"] }.each do |yelmo_id|
      city, cinema_key = yelmo_id.split("/", 2)

      refute_empty city.to_s, "#{yelmo_id.inspect} has no city"
      refute_empty cinema_key.to_s, "#{yelmo_id.inspect} has no cinema"
    end
  end

  def test_only_cinemas_that_are_filtered_need_a_second_opinion_from_yelmo
    # A yelmo_id exists to rescue original-version screenings from a filter. On
    # a venue that is not filtered it would have nothing to do.
    CINEMAS.select { |cinema| cinema["yelmo_id"] }.each do |cinema|
      assert cinema["check_vo"], "#{cinema["name"]} has a yelmo_id but is not filtered"
    end
  end
end
