# frozen_string_literal: true

require "test_helper"

class MachineReadableZoneTest < ActiveSupport::TestCase
  # Build a valid TD3 zone so the check digits are correct by construction
  # rather than copied from a real passport.
  def td3(number: "12AB34567", nationality: "NPL", birth: "900115", sex: "M",
          expiry: "310220", issuing: "NPL", surname: "BHATTARAI", given: "RAJAN")
    name_field = "#{surname}<<#{given.tr(" ", "<")}".ljust(39, "<")
    line1 = "P<#{issuing}#{name_field}"[0, 44].ljust(44, "<")

    number_field = number.ljust(9, "<")
    personal = "<" * 14
    line2 = number_field + cd(number_field).to_s + nationality +
            birth + cd(birth).to_s + sex + expiry + cd(expiry).to_s +
            personal + "<"

    composite = line2[0, 10] + line2[13, 7] + line2[21, 22]
    [ line1, line2 + cd(composite).to_s ]
  end

  def td1(number: "AB1234567", birth: "900115", expiry: "310220")
    number_field = number.ljust(9, "<")
    line1 = ("I<NPL" + number_field + cd(number_field).to_s).ljust(30, "<")
    partial = birth + cd(birth).to_s + "M" + expiry + cd(expiry).to_s + "NPL" + ("<" * 11)
    composite = line1[5, 25] + partial[0, 7] + partial[8, 7] + partial[18, 11]
    line2 = partial + cd(composite).to_s
    [ line1, line2, "BHATTARAI<<RAJAN".ljust(30, "<") ]
  end

  def cd(field) = MachineReadableZone.check_digit(field)

  test "check digits follow the 7-3-1 weighting" do
    # D=13: 13*7 + 2*3 + 3*1 + 1*7 + 4*3 + 5*1 + 8*7 + 9*3 + 0*1 + 7*7 + 3*3 + 4*1
    #     = 269, and 269 mod 10 = 9.
    assert_equal 9, MachineReadableZone.check_digit("D23145890734")
    assert_equal 2, MachineReadableZone.check_digit("740812")
  end

  test "filler characters count as zero" do
    assert_equal MachineReadableZone.check_digit("AB<<"), MachineReadableZone.check_digit("AB00")
  end

  test "parses a passport zone" do
    result = MachineReadableZone.parse(td3.join("\n"))

    assert_predicate result, :valid?
    assert_equal "TD3", result.format
    assert_predicate result, :passport?
    assert_equal "NP", result.issuing_country
    assert_equal "BHATTARAI", result.surname
    assert_equal "RAJAN", result.given_names
    assert_equal "12AB34567", result.number
    assert_equal Date.new(2031, 2, 20), result.expires_on
    assert_equal Date.new(1990, 1, 15), result.date_of_birth
  end

  test "parses an ID card zone" do
    result = MachineReadableZone.parse(td1.join("\n"))

    assert_predicate result, :valid?
    assert_equal "TD1", result.format
    assert_equal Date.new(2031, 2, 20), result.expires_on
  end

  # The whole reason for using the MRZ rather than general OCR: a misread is
  # caught instead of being stored as somebody's expiry date.
  test "rejects a corrupted expiry date" do
    lines = td3
    lines[1] = lines[1].dup.tap { |line| line[21, 6] = "310221" }

    result = MachineReadableZone.parse(lines.join("\n"))

    assert_not_predicate result, :valid?
    assert(result.errors.any? { |e| e.match?(/expiry date/) })
  end

  # Reading from a camera rather than a keyboard, the errors stop being random
  # and become a short list of shapes: O for 0, I for 1, S for 5. They land in
  # the date fields, because that is where digits are.
  test "repairs digit-shaped letters in the numeric fields" do
    lines = td3
    lines[1] = lines[1].dup.tap { |line| line[21, 6] = "3IO22O" } # 310220 misread

    result = MachineReadableZone.parse(lines.join("\n"))

    assert_predicate result, :valid?
    assert_equal Date.new(2031, 2, 20), result.expires_on
    assert_predicate result, :repaired?
  end

  test "repairs the date of birth as well as the expiry" do
    lines = td3
    lines[1] = lines[1].dup.tap { |line| line[13, 6] = "9OO115" } # 900115 misread

    result = MachineReadableZone.parse(lines.join("\n"))

    assert_predicate result, :valid?
    assert_equal Date.new(1990, 1, 15), result.date_of_birth
  end

  # The repair is allowed to rescue a failed read. It is not allowed to
  # manufacture a confident wrong date out of one, which is the only failure
  # this product genuinely cannot afford.
  test "a genuinely wrong digit is still rejected rather than repaired" do
    lines = td3
    lines[1] = lines[1].dup.tap { |line| line[21, 6] = "310221" }

    result = MachineReadableZone.parse(lines.join("\n"))

    assert_not_predicate result, :valid?
    assert_not_predicate result, :repaired?
  end

  # A document number may legitimately contain letters, so a letter there is
  # not evidence of anything and must be left alone.
  test "leaves letters in the document number untouched" do
    result = MachineReadableZone.parse(td3(number: "IO12B4567").join("\n"))

    assert_predicate result, :valid?
    assert_equal "IO12B4567", result.number
    assert_not_predicate result, :repaired?
  end

  test "says which characters it changed rather than repairing silently" do
    lines = td3
    lines[1] = lines[1].dup.tap { |line| line[21, 6] = "3IO22O" }

    result = MachineReadableZone.parse(lines.join("\n"))

    assert_equal [ "I→1", "O→0", "O→0" ], result.repaired
  end

  test "a clean read reports no repair" do
    assert_not_predicate MachineReadableZone.parse(td3.join("\n")), :repaired?
  end

  test "rejects a corrupted document number" do
    lines = td3
    lines[1] = lines[1].dup.tap { |line| line[0, 9] = "99XY99999" }

    assert_not_predicate MachineReadableZone.parse(lines.join("\n")), :valid?
  end

  test "catches a single transposed character via the composite check" do
    lines = td3
    lines[1] = lines[1].dup.tap { |line| line[43] = line[43] == "0" ? "1" : "0" }

    result = MachineReadableZone.parse(lines.join("\n"))

    assert_not_predicate result, :valid?
    assert(result.errors.any? { |e| e.match?(/checksum/) })
  end

  test "tolerates whitespace and lowercase from a paste" do
    messy = td3.map { |line| "  #{line.downcase}  " }.join("\n")

    assert_predicate MachineReadableZone.parse(messy), :valid?
  end

  test "tolerates autocorrected chevrons" do
    mangled = td3.join("\n").tr("<", "«")

    assert_predicate MachineReadableZone.parse(mangled), :valid?
  end

  test "explains itself when the shape is wrong" do
    result = MachineReadableZone.parse("not an mrz at all")

    assert_not_predicate result, :valid?
    assert_match(/44 characters/, result.errors.first)
  end

  test "asks for input when given nothing" do
    assert_match(/Enter the two lines/, MachineReadableZone.parse("").errors.first)
  end

  # An expiry two digits from now must not land in the last century.
  test "resolves the century from the direction of the date" do
    result = MachineReadableZone.parse(td3(birth: "651130", expiry: "301130").join("\n"))

    assert_equal Date.new(2030, 11, 30), result.expires_on
    assert_equal Date.new(1965, 11, 30), result.date_of_birth
  end

  test "leaves the country blank rather than guessing an unmapped code" do
    result = MachineReadableZone.parse(td3(issuing: "BRA", nationality: "BRA").join("\n"))

    assert_nil result.issuing_country
  end

  test "offers only the fields a document needs" do
    attributes = MachineReadableZone.parse(td3.join("\n")).to_document_attributes

    assert_equal "passport", attributes[:kind]
    assert_equal "NP", attributes[:issuing_country]
    assert_equal Date.new(2031, 2, 20), attributes[:expires_on]
    # Name, sex and date of birth are read but never stored: they are not needed
    # to compute a date.
    assert_not attributes.key?(:surname)
    assert_not attributes.key?(:date_of_birth)
  end

  test "an invalid date does not raise" do
    assert_nil MachineReadableZone.parse(td3(expiry: "319999").join("\n")).expires_on
  end
end
