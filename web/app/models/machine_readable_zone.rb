# frozen_string_literal: true

# Parser for the machine-readable zone printed on passports and ID cards
# (ICAO 9303, formats TD3 and TD1).
#
# This exists because cold start is the product's biggest risk: the thing is
# worth nothing until roughly fifteen documents are in it, and typing fifteen
# documents in by hand is what kills every personal-records product. The MRZ is
# the way out, and it works precisely because it is *not* general OCR — the
# layout is fixed and every field carries a check digit, so a misread is
# detected rather than silently stored as somebody's expiry date.
#
# That last property is why this is worth writing rather than trusting a
# generic text extractor: a wrong expiry date here produces a confidently wrong
# reminder, which is worse than no reminder at all.
class MachineReadableZone
  WEIGHTS = [ 7, 3, 1 ].freeze
  FILLER = "<"

  Result = Struct.new(
    :format, :document_code, :issuing_country, :surname, :given_names, :number,
    :nationality, :date_of_birth, :sex, :expires_on, :errors,
    keyword_init: true
  ) do
    def valid? = errors.empty?
    def full_name = [ given_names, surname ].compact_blank.join(" ")
    def passport? = document_code.to_s.start_with?("P")

    # What the document form needs. Nothing else about the holder is retained.
    def to_document_attributes
      { kind: passport? ? "passport" : nil, issuing_country: issuing_country, expires_on: expires_on }.compact
    end
  end

  class << self
    def parse(input)
      lines = normalise(input)

      case lines.map(&:length)
      in [ 44, 44 ] then parse_td3(lines)
      in [ 30, 30, 30 ] then parse_td1(lines)
      else
        Result.new(errors: [ shape_error(lines) ])
      end
    end

    # Fixed-width and uppercase. Cameras and copy-paste both introduce stray
    # whitespace; the spec's filler character is "<", and "«" or "≪" turn up
    # when text has been through an autocorrecting keyboard.
    def normalise(input)
      input.to_s
           .unicode_normalize(:nfkc)
           .upcase
           .tr("«≪", FILLER)
           .split(/\r?\n/)
           .map { |line| line.gsub(/[^A-Z0-9<]/, "") }
           .reject(&:empty?)
    end

    def character_value(char)
      case char
      when FILLER then 0
      when "0".."9" then char.to_i
      when "A".."Z" then char.ord - "A".ord + 10
      else 0
      end
    end

    def check_digit(field)
      field.each_char.with_index.sum { |char, index| character_value(char) * WEIGHTS[index % 3] } % 10
    end

    def check_digit_ok?(field, digit)
      # A filler in the check position means the field is unused, which the
      # standard permits for optional data.
      return true if digit == FILLER && field.chars.all?(FILLER)

      digit == check_digit(field).to_s
    end

    private

    def shape_error(lines)
      if lines.empty?
        "Enter the two lines printed along the bottom of the photo page."
      else
        "Expected 2 lines of 44 characters (passport) or 3 lines of 30 (ID card), " \
          "got #{lines.map(&:length).join(" + ")}. Include the < characters."
      end
    end

    def parse_td3(lines)
      first, second = lines
      errors = []

      surname, given_names = parse_names(first[5..])

      number = strip(second[0, 9])
      errors << "The document number did not check out — it may have been misread." unless check_digit_ok?(second[0, 9], second[9])

      birth_raw = second[13, 6]
      errors << "The date of birth did not check out." unless check_digit_ok?(birth_raw, second[19])

      expiry_raw = second[21, 6]
      errors << "The expiry date did not check out — this is the field we most need to be right." unless check_digit_ok?(expiry_raw, second[27])

      # Positions 1-10, 14-20 and 22-43 (1-indexed). The final character is the
      # composite check digit itself and must not be part of what it checks.
      composite = second[0, 10] + second[13, 7] + second[21, 22]
      errors << "The overall checksum failed, so at least one character was misread." unless check_digit_ok?(composite, second[43])

      Result.new(
        format: "TD3",
        document_code: strip(first[0, 2]),
        issuing_country: country(first[2, 3]),
        surname: surname,
        given_names: given_names,
        number: number,
        nationality: country(second[10, 3]),
        date_of_birth: parse_date(birth_raw, :past),
        sex: parse_sex(second[20]),
        expires_on: parse_date(expiry_raw, :future),
        errors: errors
      )
    end

    def parse_td1(lines)
      first, second, third = lines
      errors = []

      surname, given_names = parse_names(third)

      number = strip(first[5, 9])
      errors << "The document number did not check out — it may have been misread." unless check_digit_ok?(first[5, 9], first[14])

      birth_raw = second[0, 6]
      errors << "The date of birth did not check out." unless check_digit_ok?(birth_raw, second[6])

      expiry_raw = second[8, 6]
      errors << "The expiry date did not check out — this is the field we most need to be right." unless check_digit_ok?(expiry_raw, second[14])

      composite = first[5, 25] + second[0, 7] + second[8, 7] + second[18, 11]
      errors << "The overall checksum failed, so at least one character was misread." unless check_digit_ok?(composite, second[29])

      Result.new(
        format: "TD1",
        document_code: strip(first[0, 2]),
        issuing_country: country(first[2, 3]),
        surname: surname,
        given_names: given_names,
        number: number,
        nationality: country(second[15, 3]),
        date_of_birth: parse_date(birth_raw, :past),
        sex: parse_sex(second[7]),
        expires_on: parse_date(expiry_raw, :future),
        errors: errors
      )
    end

    def parse_names(field)
      surname, given = field.to_s.split("<<", 2)
      [ humanise(surname), humanise(given) ]
    end

    def humanise(field) = field.to_s.tr(FILLER, " ").squeeze(" ").strip.presence

    def strip(field) = field.to_s.tr(FILLER, "").strip.presence

    # The MRZ uses three-letter ICAO codes; the dataset is keyed on ISO alpha-2.
    # Only codes the dataset can actually act on are mapped — anything else is
    # left nil so the user picks, rather than being silently given the wrong
    # country.
    ICAO_TO_ISO = {
      "NPL" => "NP", "GBR" => "GB", "USA" => "US", "AUS" => "AU", "QAT" => "QA",
      "ARE" => "AE", "MYS" => "MY", "KOR" => "KR", "JPN" => "JP", "IND" => "IN",
      "CAN" => "CA", "DEU" => "DE", "PRT" => "PT", "SAU" => "SA"
    }.freeze

    def country(code) = ICAO_TO_ISO[strip(code)]

    def parse_sex(char)
      case char
      when "M" then "M"
      when "F" then "F"
      end
    end

    # YYMMDD with no century. An expiry is in the future and a birth date is in
    # the past, so the direction resolves the ambiguity — guessing the wrong
    # century on an expiry date would be catastrophic rather than cosmetic.
    def parse_date(raw, direction)
      return nil unless raw.to_s.match?(/\A\d{6}\z/)

      year = raw[0, 2].to_i
      month = raw[2, 2].to_i
      day = raw[4, 2].to_i
      return nil unless month.between?(1, 12) && day.between?(1, 31)

      century = direction == :future ? future_century(year) : past_century(year)
      Date.new(century + year, month, day)
    rescue Date::Error
      nil
    end

    def future_century(year)
      current = Date.current.year % 100
      # A passport can be valid for ten years, so allow a modest window past the
      # current year before assuming the previous century.
      year >= current - 10 ? Date.current.year / 100 * 100 : (Date.current.year / 100 + 1) * 100
    end

    def past_century(year)
      current = Date.current.year % 100
      year > current ? (Date.current.year / 100 - 1) * 100 : Date.current.year / 100 * 100
    end
  end
end
