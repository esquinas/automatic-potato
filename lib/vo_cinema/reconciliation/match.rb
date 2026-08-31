# frozen_string_literal: true

module VoCinema
  class Reconciliation
    # The film that one or more providers' records turned out to describe.
    #
    # Everything worth asking about a merge is a question about one of these:
    # which screening it became, whether the providers contradicted each other,
    # and which rule joined them. Reconciliation asks the first; Agreement asks
    # the rest.
    Match = Data.define(:records) do
      # One screening, however many providers mentioned it — and original
      # version if ANY of them said so.
      #
      # The two claims are not equally reliable. Saying "original version"
      # takes information: a bucket named for it, a diffusionVersion of
      # "ORIGINAL", a VOSE language tag. Saying "dubbed" is what a provider
      # says when it has nothing, which is why SensaCine files Yelmo's
      # subtitled prints that way, and why Yelmo labels a Spanish film
      # "ESPAÑOL" when that print is the original. A negative is an absence of
      # evidence; a positive is evidence.
      #
      # So a dubbed screening can reach the digest on one provider's bad word.
      # That is an accepted cost: the box office says which print it is before
      # anyone pays, and cinemas are far more careful about the opposite
      # mistake — an audience expecting dubbing and getting subtitles complains.
      #
      # The records were read shortest-title-first, so the first one already
      # carries the spelling that should print.
      def session = records.first.session.with(original_version?: records.any?(&:original_version?))

      def minute = records.first.minute

      def providers = records.map(&:provider).uniq

      def merged? = records.length > 1

      # Only a screening more than one provider described can be contradicted.
      def described_twice? = providers.length > 1

      def disagreed? = records.map(&:original_version?).uniq.length > 1

      # Whether the titles matched outright or the director had to rescue them.
      def by_title? = records.map(&:film).map(&:key).uniq.one?

      # The provider that was the only one calling this original version, if
      # exactly one was. Nil when they all agreed, either way.
      def sole_vo_source
        claiming = records.select(&:original_version?).map(&:provider).uniq

        claiming.first if claiming.one?
      end
    end
  end
end
