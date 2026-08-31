# frozen_string_literal: true

module VoCinema
  # A film as the digest knows it: the Spanish release title the cinemas use, the
  # year it was made, its director, and — once TMDB has been asked — its original
  # title.
  #
  # Mutable on purpose. +title+ starts nil and is filled in after the lookup;
  # making it immutable would mean rebuilding every ScreeningSession that already
  # holds the film.
  class Film
    # Only two of these are ever written: +title+ when TMDB answers, and +year+
    # when one provider dates a film the other left undated. What the cinema
    # called the film and who directed it are settled when the record is read.
    attr_accessor :title, :year
    attr_reader :localized_title, :director

    def initialize(localized_title:, year:, title: nil, director: nil)
      @title           = title
      @localized_title = localized_title
      @year            = year
      @director        = director
    end

    # The title as it is compared across providers, which disagree about capitals
    # and stray spaces.
    def key = localized_title.downcase.strip

    # Whether two providers are describing the same film.
    #
    # Usually they spell it the same way and the key settles it. When they do
    # not, the director decides: Ocimax's Harry Potter is "Harry Potter y la
    # Piedra Filosofal" on SensaCine and "…25 Aniversario" on Yelmo, and both
    # name Chris Columbus. A marketing suffix changes the title; it cannot
    # change who directed the film.
    #
    # The prefix test is what keeps that safe. Sharing a director is not enough
    # on its own — a director can have two films in one week — but a director
    # who also billed one title as an extension of the other is not a
    # coincidence. See CLAUDE.md for the evidence behind both halves.
    def same_film_as?(other)
      key == other.key || (same_director?(other) && one_title_extends_the_other?(other))
    end

    # Squeezed, because Yelmo pads some names with a double space: it writes
    # "Will  Gluck" where SensaCine writes "Will Gluck".
    def director_key = director&.split&.join(" ")&.downcase

    def ==(other)
      other.is_a?(Film) && localized_title == other.localized_title && year == other.year
    end

    alias eql? ==

    def hash
      [localized_title, year].hash
    end

    private

    # A film neither provider named a director for tells us nothing, so it is
    # never rescued this way — two untitled entries would otherwise merge on
    # having equally nothing to say.
    def same_director?(other)
      mine = director_key

      mine && mine == other.director_key
    end

    def one_title_extends_the_other?(other)
      mine, theirs = key, other.key

      mine.start_with?(theirs) || theirs.start_with?(mine)
    end
  end
end
