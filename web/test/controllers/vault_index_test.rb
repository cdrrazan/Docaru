# frozen_string_literal: true

require "test_helper"

# The screen somebody opens from another city to find one certificate. Most of a
# vault never appears on the dashboard, because most of it has no deadline —
# which is precisely why finding things has to work on its own terms.
class VaultIndexTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)

    @degree = members(:rajan).documents.create!(
      kind: "degree_certificate", issuing_country: "NP", label: "BSc Computer Science"
    )
    @deed = members(:mother).documents.create!(
      kind: "property_deed", issuing_country: "NP", label: "Lalitpur land certificate"
    )
  end

  test "requires authentication" do
    sign_out
    get documents_path

    assert_redirected_to new_session_path
  end

  test "lists everything the household holds, expiring or not" do
    get documents_path

    assert_response :success
    assert_select "a", text: "BSc Computer Science"
    assert_select "a", text: "Lalitpur land certificate"
    # The fixtures' dated documents are here too — one list, not two products.
    assert_select "a", text: "Nepali e-Passport"
  end

  # Scoped through the household, so another household's records are not
  # merely hidden from the list — they are unreachable by id.
  test "another household's documents are neither listed nor reachable" do
    get documents_path

    assert_select "a[href=?]", document_path(documents(:stranger_passport)), count: 0

    get document_path(documents(:stranger_passport))

    assert_response :not_found
  end

  test "finds a document by its label" do
    get documents_path, params: { q: "Lalitpur" }

    assert_select "a", text: "Lalitpur land certificate"
    assert_select "a", text: "BSc Computer Science", count: 0
  end

  test "finds a document by whose it is" do
    get documents_path, params: { q: "Aama" }

    assert_select "a", text: "Lalitpur land certificate"
    assert_select "a", text: "BSc Computer Science", count: 0
  end

  test "filters to one person" do
    get documents_path, params: { member_id: members(:mother).id }

    assert_select "a", text: "Lalitpur land certificate"
    assert_select "a", text: "BSc Computer Science", count: 0
  end

  test "says so rather than showing an empty page when nothing matches" do
    get documents_path, params: { q: "nothing called this" }

    assert_response :success
    assert_select ".banner", /Nothing matches/
  end

  # A LIKE query built from user input is the classic way to turn a search box
  # into something else.
  test "a wildcard in the search is treated as text" do
    get documents_path, params: { q: "%" }

    assert_response :success
    assert_select ".banner", /Nothing matches/
  end

  # identifier and notes are encrypted precisely so the server cannot read them.
  # Searching them would require it to.
  test "encrypted fields are not searchable" do
    @degree.update!(identifier: "SECRETNUMBER123")

    get documents_path, params: { q: "SECRETNUMBER123" }

    assert_select ".banner", /Nothing matches/
  end

  test "a document with no expiry reads as stored rather than incomplete" do
    get document_path(@degree)

    assert_response :success
    assert_select ".answer .headline", text: "Stored"
    assert_select "body", /does not expire/
    # Not "we have no renewal rule for your degree certificate", which would be
    # answering a question nobody asked.
    assert_no_match(/No renewal rule for this document yet/, response.body)
    assert_select "body", /nothing to remind you about/
  end
end
