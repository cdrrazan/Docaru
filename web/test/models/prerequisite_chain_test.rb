# frozen_string_literal: true

require "test_helper"

class PrerequisiteChainTest < ActiveSupport::TestCase
  setup do
    Document.delete_all
    @member = members(:rajan)
  end

  def bluebook(expires_in: 300.days)
    @member.documents.create!(kind: "vehicle_registration", issuing_country: "NP",
                              applying_from: "GB", expires_on: expires_in.from_now.to_date)
  end

  def insurance(expires_in:, member: @member)
    member.documents.create!(kind: "insurance_policy", issuing_country: "NP",
                             expires_on: expires_in.from_now.to_date)
  end

  test "reads the dependency out of the rules dataset" do
    chain = bluebook.chain

    assert_predicate chain, :any?
    assert_equal "insurance_policy", chain.links.sole.document_kind
  end

  test "a document with no dependencies has an empty chain" do
    passport = @member.documents.create!(kind: "passport", issuing_country: "NP",
                                         expires_on: 2.years.from_now.to_date)

    assert_not_predicate passport.chain, :any?
  end

  test "says so when the prerequisite is not tracked at all" do
    chain = bluebook.chain

    assert_equal :missing, chain.links.sole.status
    assert_not_predicate chain, :blocking?
    assert_equal 1, chain.untracked.size
  end

  test "is satisfied when the prerequisite outlasts the renewal" do
    doc = bluebook(expires_in: 300.days)
    insurance(expires_in: 3.years)

    assert_equal :ok, doc.chain.links.sole.status
    assert_not_predicate doc.chain, :blocking?
  end

  # The headline case. Nobody spots this by looking at two expiry dates.
  test "flags a prerequisite that lapses before the renewal needs it" do
    doc = bluebook(expires_in: 300.days)
    insurance(expires_in: 40.days)

    link = doc.chain.links.sole

    assert_equal :expires_first, link.status
    assert_predicate doc.chain, :blocking?
    assert_operator link.document.expires_on, :<, doc.start_by
  end

  # The prerequisite outlasts the moment it is needed, but only just — its own
  # renewal falls first, so the two have to be done in order.
  test "flags a prerequisite that has to be renewed first" do
    doc = bluebook(expires_in: 400.days)
    # Survives the moment it is needed, but only just — so its own renewal
    # window opens before the dependent one's.
    prerequisite = @member.documents.create!(
      kind: "insurance_policy", issuing_country: "NP", expires_on: doc.start_by + 5
    )

    assert_operator prerequisite.expires_on, :>=, doc.start_by
    assert_operator prerequisite.start_by, :<=, doc.start_by
    assert_equal :also_due, doc.chain.links.sole.status
    assert_predicate doc.chain, :blocking?
  end

  test "prefers the same person's copy of the prerequisite" do
    mine = bluebook(expires_in: 300.days)
    insurance(expires_in: 3.years, member: members(:mother))
    ours = insurance(expires_in: 3.years)

    assert_equal ours, mine.chain.links.sole.document
  end

  test "never matches a document from another household" do
    doc = bluebook(expires_in: 300.days)
    members(:stranger).documents.create!(kind: "insurance_policy", issuing_country: "NP",
                                         expires_on: 3.years.from_now.to_date)

    assert_equal :missing, doc.chain.links.sole.status
  end

  test "does not treat a document as its own prerequisite" do
    doc = bluebook(expires_in: 300.days)

    assert_not_equal doc, doc.chain.links.sole.document
  end
end
