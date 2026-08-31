# frozen_string_literal: true

module VoCinema
  # Several providers' accounts of one cinema's week, read as one.
  #
  # Ocimax is described by both SensaCine and Yelmo, so the same screening
  # arrives twice. This is where the two accounts become one, and it answers two
  # questions about every screening: which film it is, and whether it is the
  # original version. #agreement answers a third — how much the providers
  # agreed on the way — over the same grouping, computed once.
  #
  # Built from [provider_name, sessions] pairs rather than a Hash, so two
  # providers answering to the same name degrade the report rather than losing
  # one of their weeks.
  #
  # Pure, and independent of the order the providers were given in — but only
  # because it sorts the records at a minute before grouping them, which is
  # load-bearing rather than tidiness. See CLAUDE.md, "Matching a film across
  # providers".
  class Reconciliation
    def initialize(weeks)
      @weeks = weeks
    end

    def sessions = matches.map(&:session)

    def agreement = Agreement.new(matches)

    private

    # Which records turned out to describe the same film. Both public queries
    # read this, so it is worked out once.
    def matches
      @matches ||= begin
        SharedYears.new(records.map(&:film)).lend

        records.group_by(&:minute).flat_map { |_minute, together| one_per_film(together) }
      end
    end

    def records
      @records ||= @weeks.flat_map do |provider, week|
        week.map { |session| Record.new(provider: provider, session: session) }
      end
    end

    # Two records at the same cinema, day and minute either describe one
    # screening or two films showing side by side in different screens — which
    # is common in a multiplex, so the film has to decide.
    #
    # The sort is what keeps the answer a function of the records rather than
    # of the order they arrived in. Film#same_film_as? is not transitive — a
    # bare title can match two different suffixed ones that do not match each
    # other — so which records group depends on which is compared first. Reading
    # them shortest-title-first settles that the same way every run, whatever
    # order the providers were asked in, and makes each group's first record the
    # one whose spelling gets printed.
    def one_per_film(at_one_minute)
      at_one_minute.sort_by { |record| spelling_rank(record.film) }
                   .each_with_object([]) { |record, films| place(record, films) }
                   .map { |group| Match.new(records: group) }
    end

    def place(record, films)
      group = films.find { |other| record.film.same_film_as?(other.first.film) }

      group ? group << record : films << [record]
    end

    # Whose spelling the digest prints. The shortest wins, because the records
    # that needed rescuing differ by a marketing suffix and the title without it
    # is the film's real name — "Harry Potter y la Piedra Filosofal", not
    # "…25 Aniversario". The alphabetical tiebreak carries no meaning beyond
    # settling "La Sustancia" against "La sustancia" the same way every run;
    # a rule with an opinion about capitals is still wanted.
    def spelling_rank(film)
      printed = film.localized_title

      [printed.length, printed]
    end

  end
end
