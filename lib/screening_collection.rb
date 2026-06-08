# frozen_string_literal: true

require_relative "constants"

class ScreeningCollection
  attr_reader :film, :rating, :sessions

  def initialize(film, rating, sessions)
    @film = film
    @rating = rating
    @sessions = sessions
  end

  def dates_map
    @dates_map ||= @sessions
      .group_by(&:date)
      .transform_values { |ss| ss.map(&:starts_at).sort.uniq }
      .sort.to_h
  end

  def all_times
    dates_map.values.flatten.sort.uniq
  end

  def full_week?
    dates_map.keys.length == WEEK_DAYS
  end
end
