# frozen_string_literal: true

require "test_helper"

class MembersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "requires authentication" do
    sign_out
    get members_path

    assert_redirected_to new_session_path
  end

  test "lists only this household's people" do
    get members_path

    assert_response :success
    assert_select "h3", text: "Aama"
    assert_select "h3", text: "Not Your Business", count: 0
  end

  test "adds a person" do
    assert_difference "households(:one).members.count", 1 do
      post members_path, params: { member: { name: "Bhai", relationship: "Brother" } }
    end

    assert_redirected_to members_path
  end

  test "rejects a person with no name" do
    assert_no_difference "Member.count" do
      post members_path, params: { member: { name: "" } }
    end

    assert_response :unprocessable_entity
  end

  test "refuses to exceed the plan's member limit" do
    sign_out
    sign_in_as users(:two) # free plan, limit of one

    households(:two).members.create!(name: "Already here") if households(:two).members.empty?

    assert_no_difference "Member.count" do
      post members_path, params: { member: { name: "One too many" } }
    end

    assert_response :unprocessable_entity
    assert_select ".errors", /plan covers/
  end

  # The important one. Another household's member id must read as missing rather
  # than forbidden — a 403 would confirm the record exists.
  test "cannot touch a member of another household" do
    stranger = members(:stranger)

    get edit_member_path(stranger)

    assert_response :not_found

    patch member_path(stranger), params: { member: { name: "Hijacked" } }

    assert_response :not_found

    delete member_path(stranger)

    assert_response :not_found
    assert_equal "Not Your Business", stranger.reload.name
    assert_predicate Member.where(id: stranger.id), :exists?
  end

  test "removing a person removes their documents" do
    member = members(:mother)

    assert_difference "Document.count", -member.documents.count do
      delete member_path(member)
    end
  end
end
