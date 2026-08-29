# frozen_string_literal: true

# A film as the digest knows it: the Spanish release title the cinemas use, the
# year it was made, and — once TMDB has been asked — its original title.
#
# Mutable on purpose. +title+ starts nil and is filled in after the lookup;
# making it immutable would mean rebuilding every ScreeningSession that already
# holds the film.
class Film
  attr_accessor :title, :localized_title, :year

  def initialize(localized_title:, year:, title: nil)
    @title           = title
    @localized_title = localized_title
    @year            = year
  end

  # The title as it is compared across providers, which disagree about capitals
  # and stray spaces.
  def key = localized_title.downcase.strip

  def ==(other)
    other.is_a?(Film) && localized_title == other.localized_title && year == other.year
  end

  alias eql? ==

  def hash
    [localized_title, year].hash
  end
end
