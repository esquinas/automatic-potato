# frozen_string_literal: true

module VoCinema
  # Several providers' accounts of one cinema's week, read as one.
  #
  # Ocimax is described by both SensaCine and Yelmo, so the same screening
  # arrives twice. This is where the two accounts become one, and it answers two
  # questions about every screening: which film it is, and whether it is the
  # original version.
  #
  # Pure, and free of the order the providers were given in — deliberately, so
  # that adding a provider cannot silently change what a subscriber reads. See
  # CLAUDE.md, "Matching a film across providers", for the evidence behind the
  # rules and what is still open about them.
  class Reconciliation
    def initialize(weeks)
      @weeks = weeks
    end

    def sessions
      lend_known_years

      all.group_by { |session| [session.date, session.starts_at] }
         .flat_map { |_minute, together| one_per_film(together) }
    end

    private

    def all = @weeks.flatten

    # Two records at the same cinema, day and minute either describe one
    # screening or two films showing side by side in different screens — which
    # is common in a multiplex, so the film has to decide.
    def one_per_film(sessions)
      sessions.each_with_object([]) { |session, films| place(session, films) }
              .map { |group| agreed(group) }
    end

    def place(session, films)
      film  = session.film
      group = films.find { |other| film.same_film_as?(other.first.film) }

      group ? group << session : films << [session]
    end

    # One screening, however many providers mentioned it — and original version
    # if ANY of them said so.
    #
    # The two claims are not equally reliable. Saying "original version" takes
    # information: a bucket named for it, a diffusionVersion of "ORIGINAL", a
    # VOSE language tag. Saying "dubbed" is what a provider says when it has
    # nothing, which is why SensaCine files Yelmo's subtitled prints that way,
    # and why Yelmo labels a Spanish film "ESPAÑOL" when that print is the
    # original. A negative is an absence of evidence; a positive is evidence.
    #
    # So a dubbed screening can reach the digest on one provider's bad word.
    # That is an accepted cost: the box office says which print it is before
    # anyone pays, and cinemas are far more careful about the opposite mistake
    # — an audience expecting dubbing and getting subtitles complains.
    def agreed(group)
      group.min_by { |session| spelling_rank(session.film) }
           .with(original_version?: group.any?(&:original_version?))
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

    # Only SensaCine reports a year, and a Film is only the same film when the
    # year matches too. Without this, Yelmo's copy of a film both providers
    # list reaches the digest as a second, yearless film of the same name —
    # printed twice, with the week's showtimes split between the two entries.
    def lend_known_years
      all.map(&:film).group_by(&:key).each_value { |sharing_a_title| lend_within(sharing_a_title) }
    end

    def lend_within(films)
      known = films.map(&:year).compact.first

      films.each { |film| film.year ||= known }
    end
  end
end
