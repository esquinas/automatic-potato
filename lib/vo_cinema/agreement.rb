# frozen_string_literal: true

module VoCinema
  # How much the providers agreed about one cinema's week.
  #
  # The union rule hides a failing provider: if Yelmo stops tagging VOSE,
  # SensaCine's records still carry the screenings, the merge still produces a
  # digest, and the only symptom is a thinner one — indistinguishable from a
  # quiet week. Where two providers describe the same venue, the rate at which
  # they contradict each other is a free drift detector.
  #
  # Read it knowing that at Ocimax **disagreement is the healthy state**:
  # SensaCine files Yelmo's subtitled prints as dubbed, so Yelmo is routinely
  # the only one calling a screening original version. Zero disagreements over
  # a non-zero #overlapping means one of them has changed shape.
  #
  # Pure: it counts the matches Reconciliation made and asks nobody anything.
  class Agreement
    def initialize(matches)
      @matches = matches
    end

    # Whether two providers described this cinema at all. One voice cannot be
    # contradicted, so a venue with only one has no health signal to give.
    def comparable? = @matches.flat_map(&:providers).uniq.length > 1

    # The screenings more than one provider described — the denominator.
    # Counting every match would drown the rate in venues where a single
    # provider is the only voice and agreement is therefore meaningless.
    #
    # This can be zero while #unmatched is not, which is the loudest signal the
    # report has: both providers are talking and nothing they say lines up.
    def overlapping = described_twice.length

    def disagreed = described_twice.count(&:disagreed?)

    # The providers that were, for some screening, the only one calling it
    # original version. If this empties while #overlapping stays high, whoever
    # used to appear here has stopped tagging.
    def sole_vo_source = described_twice.filter_map(&:sole_vo_source).uniq.sort

    # Which rule did the merging. A change to the matching that makes
    # #by_director jump is visible here instead of silent.
    def by_title = merged.count(&:by_title?)

    def by_director = merged.length - by_title

    # Records left on their own at a minute more than one provider reported on:
    # the population the director rescue is trying to reach.
    def unmatched = contested.flatten(1).count { |match| !match.merged? }

    private

    def merged = @matches.select(&:merged?)

    def described_twice = @matches.select(&:described_twice?)

    # The minutes where the providers had more than one voice between them.
    def contested
      @matches.group_by(&:minute)
              .values
              .select { |at_one_minute| at_one_minute.flat_map(&:providers).uniq.length > 1 }
    end
  end
end
