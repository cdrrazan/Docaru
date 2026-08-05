# frozen_string_literal: true

require "test_helper"

class RenewalCalculationTest < ActiveSupport::TestCase
  def calc(**overrides)
    RenewalCalculation.new(
      { country_code: "NP", document_kind: "passport", expires_on: Date.current + 2.years }.merge(overrides)
    )
  end

  test "requires a document and an expiry date" do
    calculation = RenewalCalculation.new

    assert_not_predicate calculation, :valid?
    assert_predicate calculation.errors[:document_kind], :any?
    assert_predicate calculation.errors[:expires_on], :any?
  end

  test "rejects a document with no rule" do
    assert_not_predicate calc(document_kind: "hunting_permit"), :valid?
  end

  # A mistyped year should not produce a confident answer about the year 4025.
  test "rejects an implausible expiry date" do
    assert_not_predicate calc(expires_on: Date.current + 60.years), :valid?
    assert_not_predicate calc(expires_on: Date.current - 60.years), :valid?
  end

  test "start_by is the expiry date less the total lead time" do
    calculation = calc(expires_on: Date.new(2027, 12, 31))
    expected = Date.new(2027, 12, 31) - calculation.timeline.start_days_before_expiry

    assert_equal expected, calculation.start_by
  end

  test "applying from abroad gives an earlier start date than applying at home" do
    home = calc(applying_from: "domestic")
    abroad = calc(applying_from: "GB")

    assert_operator abroad.start_by, :<, home.start_by
  end

  test "never advises starting before the renewal window opens" do
    calculation = calc(expires_on: Date.current + 5.years)

    assert_operator calculation.start_by, :>=, calculation.window_opens_on
  end

  test "is comfortable when the deadline is far away" do
    assert_equal :ahead, calc(expires_on: Date.current + 3.years).status
  end

  test "says start now when the start date is imminent" do
    calculation = calc(expires_on: Date.current + 190.days, applying_from: "GB")

    assert_equal :now, calculation.status
    assert_match(/Start/, calculation.headline)
  end

  # Being told plainly that you are late is more useful than a soothing date
  # that has already passed.
  test "says how late you already are" do
    calculation = calc(expires_on: Date.current + 30.days, applying_from: "GB")

    assert_equal :overdue, calculation.status
    assert_match(/should have started/, calculation.headline)
  end

  test "reports an already-expired document as expired" do
    calculation = calc(expires_on: Date.current - 10.days)

    assert_equal :expired, calculation.status
    assert_match(/expired 10 days ago/, calculation.headline)
  end

  test "reports an impossible window rather than inventing a date" do
    calculation = calc(document_kind: "drivers_licence", expires_on: Date.current + 3.years)

    assert_equal :impossible, calculation.status
    assert_match(/cannot finish/, calculation.headline)
    assert_operator calculation.projected_completion, :>, calculation.expires_on
  end

  test "document options only offer documents that have a rule" do
    values = RenewalCalculation.document_options.map(&:last)

    assert_includes values, "NP:passport"
    values.each do |value|
      country, kind = value.split(":")

      assert RuleCatalog.find(country, kind), "#{value} has no rule"
    end
  end
end
