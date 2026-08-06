# frozen_string_literal: true

module Docaru
  # ISO 3166-1 alpha-2 to the phrasing a reader would actually use, including
  # the definite article where English wants one ("from the United Kingdom",
  # not "from United Kingdom"). Shared by the static generator and the web app
  # so the two never drift.
  module Countries
    NAMES = {
      "AE" => "the United Arab Emirates",
      "AU" => "Australia",
      "CA" => "Canada",
      "DE" => "Germany",
      "GB" => "the United Kingdom",
      "IN" => "India",
      "JP" => "Japan",
      "KR" => "South Korea",
      "MY" => "Malaysia",
      "NP" => "Nepal",
      "PT" => "Portugal",
      "QA" => "Qatar",
      "SA" => "Saudi Arabia",
      "US" => "the United States"
    }.freeze

    # Unknown codes fall back to the code itself rather than raising: a rule for
    # a country nobody has added a name for should still render.
    def self.name(code) = NAMES.fetch(code.to_s.upcase, code.to_s)

    # Heading form: drops the leading article so "the United Kingdom" reads as
    # "United Kingdom" in a list or a chip. Deliberately does not call capitalize
    # — the names are already correctly cased, and capitalize would downcase the
    # rest of the string, turning "United Kingdom" into "United kingdom".
    def self.title(code) = name(code).delete_prefix("the ")
  end
end
