# frozen_string_literal: true

require "test_helper"

class DocumentsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "requires authentication" do
    sign_out
    get document_path(documents(:passport))

    assert_redirected_to new_session_path
  end

  test "shows a document with its start date and alert schedule" do
    get document_path(documents(:passport))

    assert_response :success
    assert_select ".answer .headline"
    assert_select "h2", text: "When we will contact you"
  end

  test "creates a document and confirms the start date immediately" do
    assert_difference "Document.count", 1 do
      post documents_path, params: { document: {
        member_id: members(:rajan).id, kind: "passport", issuing_country: "NP",
        applying_from: "GB", expires_on: 3.years.from_now.to_date.to_s
      } }
    end

    follow_redirect!

    assert_match(/Start by/, flash[:notice] || response.body)
  end

  test "does not pretend a missing rule produced a start date" do
    post documents_path, params: { document: {
      member_id: members(:rajan).id, kind: "warranty", issuing_country: "DE",
      expires_on: 1.year.from_now.to_date.to_s
    } }

    assert_match(/no renewal rule/i, flash[:notice])
  end

  test "rejects a document with no expiry date" do
    assert_no_difference "Document.count" do
      post documents_path, params: { document: {
        member_id: members(:rajan).id, kind: "passport", issuing_country: "NP", expires_on: ""
      } }
    end

    assert_response :unprocessable_entity
  end

  # A member id belonging to somebody else must not become a way to write into
  # their household.
  test "cannot attach a document to another household's member" do
    assert_no_difference "Document.count" do
      post documents_path, params: { document: {
        member_id: members(:stranger).id, kind: "passport", issuing_country: "NP",
        expires_on: 1.year.from_now.to_date.to_s
      } }
    end

    assert_response :unprocessable_entity
  end

  test "cannot read or change another household's document" do
    stranger = documents(:stranger_passport)

    get document_path(stranger)

    assert_response :not_found

    patch document_path(stranger), params: { document: { label: "Hijacked" } }

    assert_response :not_found

    delete document_path(stranger)

    assert_response :not_found
    assert_predicate Document.where(id: stranger.id), :exists?
  end

  test "refuses to exceed the plan's document limit" do
    household = households(:one)
    household.update!(plan: "free")
    household.documents.count.upto(19) do
      members(:rajan).documents.create!(kind: "passport", issuing_country: "NP", expires_on: 2.years.from_now.to_date)
    end

    assert_no_difference "Document.count" do
      post documents_path, params: { document: {
        member_id: members(:rajan).id, kind: "passport", issuing_country: "NP",
        expires_on: 2.years.from_now.to_date.to_s
      } }
    end

    assert_response :unprocessable_entity
    assert_select ".errors", /plan covers/
  end

  test "editing the expiry date clears sent reminders so the cascade reruns" do
    document = documents(:passport)
    document.reminders.create!(kind: "start_in_30", scheduled_for: Date.current, sent_at: Time.current)

    patch document_path(document), params: { document: { expires_on: 5.years.from_now.to_date.to_s } }

    assert_equal 0, document.reminders.count
  end
end
