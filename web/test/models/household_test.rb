# frozen_string_literal: true

require "test_helper"

class HouseholdTest < ActiveSupport::TestCase
  test "requires a name" do
    assert_not_predicate Household.new(name: ""), :valid?
  end

  test "rejects an unknown plan" do
    assert_not_predicate Household.new(name: "x", plan: "platinum"), :valid?
  end

  test "defaults to the free plan" do
    assert_equal "free", Household.create!(name: "New").plan
  end

  test "free plan caps documents and people" do
    household = Household.create!(name: "Free one")

    assert_equal 20, household.document_limit
    assert_equal 1, household.member_limit
  end

  test "paid plan lifts the document cap" do
    assert_predicate Household.new(plan: "household").document_limit, :infinite?
    assert_equal 6, Household.new(plan: "household").member_limit
  end

  test "reports remaining capacity without going negative" do
    household = households(:two)
    household.members.create!(name: "A")

    assert_equal 0, household.members_remaining
    assert_not_predicate household, :can_add_member?
  end

  # Reminders are the safety feature. Gating them on billing state would mean
  # somebody loses their visa over a lapsed subscription, which is exactly the
  # trust position the product cannot afford to give up.
  test "alerting is never gated by plan" do
    Household::PLANS.each do |plan|
      assert_predicate Household.new(name: "x", plan: plan), :alerting?
    end
  end

  test "documents reach the household through members" do
    assert_includes households(:one).documents, documents(:passport)
    assert_not_includes households(:one).documents, documents(:stranger_passport)
  end
end
