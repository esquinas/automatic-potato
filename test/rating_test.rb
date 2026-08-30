# frozen_string_literal: true


# Rating is a null object. Callers push it into a list of message parts and
# join them; a film TMDB could not rate contributes nothing rather than
# forcing a conditional at every call site.
class RatingTest < ServiceTest
  def test_this_is_what_a_rating_looks_like_in_the_digest
    # The one place the exact presentation is pinned down. If the star or the
    # spacing ever changes on purpose, this is the test to update.
    assert_equal "★ 7.9", Rating.new(score: 7.903).to_s
  end

  def test_a_score_is_shown_to_a_single_decimal
    # TMDB reports "La sustancia" as 7.131; three decimals is more precision
    # than anyone choosing a film on a Monday morning needs.
    shown = Rating.new(score: 7.131).to_s

    assert_includes shown, "7.1"
    refute_includes shown, "7.131"
  end

  def test_a_film_tmdb_could_not_rate_shows_nothing_at_all
    assert_equal "", Rating.null.to_s
  end

  def test_a_missing_rating_leaves_no_gap_in_a_title_line
    parts = ["<b>El ser querido</b>", Rating.null]

    assert_equal "<b>El ser querido</b>", parts.join(" ").strip
  end

  def test_a_known_rating_joins_onto_a_title_line
    parts = ["<b>La sustancia</b>", "<i>(The Substance)</i>", Rating.new(score: 7.131)]

    assert_equal "<b>La sustancia</b> <i>(The Substance)</i> ★ 7.1", parts.join(" ").strip
  end

  def test_a_rating_can_stand_in_for_a_string_without_being_converted_first
    # to_str is what lets String#+ and Array#join accept a Rating directly.
    assert_equal "Puntuación: ★ 6.8", "Puntuación: " + Rating.new(score: 6.8)
  end

  def test_the_null_rating_holds_no_score
    assert_nil Rating.null.score
  end

  def test_the_null_rating_cannot_be_altered_by_one_caller_for_everybody_else
    assert_predicate Rating.null, :frozen?
  end
end
