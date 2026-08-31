# frozen_string_literal: true

module VoCinema
  class Reconciliation
    # The week's films, with the years shared out among them.
    #
    # Only SensaCine reports a year, and a Film is only the same film when the
    # year matches too. Left alone, Yelmo's yearless copy of a film both
    # providers list reaches the digest as a second film of the same name —
    # printed twice, with the week's showtimes split between the two entries.
    #
    # This runs before anything is grouped, because it is what makes the films
    # comparable in the first place; it has nothing to do with deciding which
    # records describe the same screening, which is the rest of Reconciliation.
    class SharedYears
      def initialize(films)
        @films = films
      end

      # Mutates the films in place. Film is a mutable PORO precisely so that
      # this does not have to rebuild every ScreeningSession holding one.
      def lend
        @films.group_by(&:key).each_value { |sharing_a_title| lend_within(sharing_a_title) }
      end

      private

      def lend_within(films)
        known = films.map(&:year).compact.first

        films.each { |film| film.year ||= known }
      end
    end
  end
end
