# frozen_string_literal: true

require "test_helper"

class CalculationsControllerTest < ActionDispatch::IntegrationTest
  test "shows an empty form with no answer" do
    get calculator_path

    assert_response :success
    assert_select "h1", "When should I start?"
    assert_select ".answer .headline", false
  end

  test "answers a complete question" do
    get calculator_path, params: { document: "NP:passport", from: "GB", expires_on: 2.years.from_now.to_date.to_s }

    assert_response :success
    assert_select ".answer .headline", /Start on/
    assert_select "td", /Start by/
  end

  # The URL carries the whole question, so an answer can be pasted into a forum
  # reply — which is also the distribution channel.
  test "the result is reachable from the url alone" do
    params = { document: "NP:passport", from: "GB", expires_on: "2028-06-30" }
    get calculator_path, params: params
    first = response.body

    get calculator_path, params: params

    assert_equal first, response.body
  end

  test "reports errors instead of guessing" do
    get calculator_path, params: { document: "NP:passport" }

    assert_response :success
    assert_select ".errors", /expiry date/
  end

  test "warns when the window cannot fit the process" do
    get calculator_path, params: { document: "NP:drivers_licence", expires_on: 2.years.from_now.to_date.to_s }

    assert_response :success
    assert_select ".answer-warn"
  end

  test "an unknown document does not blow up" do
    get calculator_path, params: { document: "NP:hunting_permit", expires_on: "2028-01-01" }

    assert_response :success
    assert_select ".errors"
  end

  test "garbage input does not blow up" do
    get calculator_path, params: { document: "nonsense", expires_on: "not-a-date" }

    assert_response :success
  end
end
