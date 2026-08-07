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

  test "free plan caps storage and people" do
    household = Household.create!(name: "Free one")

    assert_equal 1.gigabyte, household.storage_limit
    assert_equal 1, household.member_limit
  end

  test "paid plans raise the storage ceiling" do
    assert_equal 25.gigabytes, Household.new(plan: "household").storage_limit
    assert_equal 100.gigabytes, Household.new(plan: "archive").storage_limit
    assert_equal 6, Household.new(plan: "household").member_limit
  end

  # Somebody running their own instance is limited by their own disk, and
  # dividing by that to draw a bar is not a sum anyone should attempt.
  test "self-hosted has no ceiling and therefore no bar to draw" do
    household = Household.new(plan: "self_hosted")

    assert_predicate household.storage_limit, :infinite?
    assert_nil household.storage_fraction
    assert_nil household.scans_remaining
  end

  test "counts the bytes actually stored, across every member" do
    household = households(:one)
    before = household.storage_used

    document = members(:rajan).documents.create!(kind: "passport", issuing_country: "NP")
    document.attachments.create!(
      iv: "YWJjZGVmZ2hpamts", content_type: "image/webp", byte_size: 400.kilobytes, page_no: 1
    )

    assert_equal before + 400.kilobytes, household.reload.storage_used
  end

  test "refuses an upload that would cross the ceiling, and allows one that fits" do
    household = households(:one)
    household.update!(plan: "free")

    assert household.can_store?(1.megabyte)
    assert_not household.can_store?(2.gigabytes)
  end

  # A downgrade leaves a household over its limit. Nothing is deleted — what it
  # loses is room to add more, not what it already trusted us with.
  test "being over the limit costs capacity, not what is already stored" do
    household = households(:one)
    household.update!(plan: "free")
    document = members(:rajan).documents.create!(kind: "passport", issuing_country: "NP")
    # Constructed, not accumulated: one page is capped at 10MB, and the subject
    # here is the household total rather than that per-page rule.
    over = document.attachments.new(
      iv: "YWJjZGVmZ2hpamts", content_type: "image/webp", byte_size: 1.gigabyte + 1, page_no: 1
    )
    over.save!(validate: false)

    household.reload

    assert_predicate household, :over_storage_limit?
    assert_equal 0, household.storage_remaining
    assert_not household.can_store?(1)
    # The safety feature is untouched by any of it.
    assert_predicate household, :alerting?
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
