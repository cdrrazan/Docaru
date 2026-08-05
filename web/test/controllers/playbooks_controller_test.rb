# frozen_string_literal: true

require "test_helper"

class PlaybooksControllerTest < ActionDispatch::IntegrationTest
  test "index lists every document" do
    get playbooks_path

    assert_response :success
    assert_select "h1", "Renewal playbooks"
    assert_select "a", text: "Nepali e-Passport"
  end

  test "shows the domestic playbook" do
    get playbook_path(country_code: "np", document_kind: "passport")

    assert_response :success
    assert_select "h1", /Nepali e-Passport renewal in Nepal/
  end

  test "shows a per-origin playbook" do
    get origin_playbook_path(country_code: "np", document_kind: "passport", origin: "gb")

    assert_response :success
    assert_select "h1", /from the United Kingdom/
  end

  # The whole product is this number. If it stops appearing, nothing else matters.
  test "leads with the start-by date" do
    get playbook_path(country_code: "np", document_kind: "passport")

    assert_select ".answer .headline", /Start \d+ days before it expires/
  end

  test "warns prominently when the process cannot fit its own window" do
    get playbook_path(country_code: "np", document_kind: "drivers-licence")

    assert_response :success
    assert_select ".answer-warn"
    assert_select ".banner-warn", /window is shorter than the process/
  end

  test "marks unverified rules as unverified" do
    get playbook_path(country_code: "np", document_kind: "passport")

    assert_select ".banner-draft", /unverified/i
  end

  test "renders the prerequisite lead time that drives the date" do
    get origin_playbook_path(country_code: "np", document_kind: "vehicle-registration", origin: "us")

    assert_response :success
    assert_select "td", /Power of attorney/
  end

  test "unknown document returns not found rather than an error" do
    get playbook_path(country_code: "np", document_kind: "hunting-permit")

    assert_response :not_found
  end

  test "unknown country returns not found" do
    get playbook_path(country_code: "zz", document_kind: "passport")

    assert_response :not_found
  end
end
