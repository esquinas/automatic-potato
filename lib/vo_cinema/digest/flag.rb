# frozen_string_literal: true

module VoCinema
  module Digest
    # The flag for a country, from its ISO 3166 code: "ES" is 🇪🇸, "US" is 🇺🇸.
    #
    # An emoji flag is nothing but the code's two letters written as Unicode
    # regional indicators, so no table is needed and no country is missing from
    # one. Anything that is not a two-letter code has no flag, and answers with
    # an empty string the title line leaves out, as it does Rating.null.
    module Flag
      REGIONAL_OFFSET = 0x1F1E6 - "A".ord

      def self.for(code)
        letters = code.to_s.upcase
        return "" unless letters.match?(/\A[A-Z]{2}\z/)

        letters.each_char.map { |letter| (letter.ord + REGIONAL_OFFSET).chr(Encoding::UTF_8) }.join
      end
    end
  end
end
