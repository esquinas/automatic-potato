# frozen_string_literal: true

Cinema = Data.define(:id, :name, :url, :check_vo?) do
  def self.from_h(hash)
    new(
      id:        hash.fetch("id"),
      name:      hash.fetch("name"),
      url:       hash["url"],
      check_vo?: hash.fetch("check_vo", false)
    )
  end
end
