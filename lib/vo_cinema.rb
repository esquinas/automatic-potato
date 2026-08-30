# frozen_string_literal: true

require "zeitwerk"

Zeitwerk::Loader.for_gem.setup

# The weekly digest of original-version screenings in Gijón.
#
# Everything lives under this namespace, in folders that name the layer:
#
#   http/        the only code that touches the network
#   showtimes/   the cinema providers, one class each
#   movies/      what TMDB knows about a film
#   digest/      turning a week into the text a subscriber reads
#   messengers/  delivering that text, each knowing its own medium
#
# Zeitwerk maps those paths to constants, so there is not a require_relative
# anywhere below this file: VoCinema::Showtimes::Sensacine lives exactly where
# its name says it does.
module VoCinema
end
