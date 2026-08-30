# frozen_string_literal: true

require "yaml"

module VoCinema
  # A venue as config/cinemas.yml describes it.
  #
  # Each provider has its own idea of what identifies a cinema — SensaCine uses
  # a theatre code, Yelmo a "city-key/cinema-key" pair — so both are named for
  # what they are and each provider reads only its own. A venue the provider
  # cannot identify simply has nothing to say about it.
  Cinema = Data.define(:name, :url, :sensacine_id, :yelmo_id, :check_vo) do
    CONFIG = File.expand_path("../../config/cinemas.yml", __dir__)

    def self.all(path: CONFIG)
      YAML.load_file(path).fetch("cinemas").map { |entry| from_config(entry) }
    end

    def self.from_config(entry)
      new(
        name:         entry["name"],
        url:          entry["url"],
        sensacine_id: entry["sensacine_id"],
        yelmo_id:     entry["yelmo_id"],
        # Venues that programme in original version by policy carry no flag;
        # filtering their listings would empty the section.
        check_vo:     entry.fetch("check_vo", false)
      )
    end
  end
end
