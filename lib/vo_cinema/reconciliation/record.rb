# frozen_string_literal: true

module VoCinema
  class Reconciliation
    # One provider's account of one screening, with the provider's name riding
    # along.
    #
    # The name has to be carried rather than looked up afterwards.
    # ScreeningSession is a Data.define and so compares by value: two providers
    # describing the same screening produce records that are `==` and hash
    # alike, which means they cannot be told apart once separated from the list
    # they arrived in. A Hash keyed by session would silently merge them.
    Record = Data.define(:provider, :session) do
      def film = session.film

      def original_version? = session.original_version?

      # One cinema, one day, one minute — the window inside which two records
      # might be describing the same screening.
      def minute = [session.date, session.starts_at]
    end
  end
end
