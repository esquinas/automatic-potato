# frozen_string_literal: true

class Film
  attr_accessor :title, :localized_title, :year

  def initialize(localized_title:, year:, title: nil)
    @title           = title
    @localized_title = localized_title
    @year            = year
  end

  def ==(other)
    other.is_a?(Film) && localized_title == other.localized_title && year == other.year
  end

  alias eql? ==

  def hash
    [localized_title, year].hash
  end
end
