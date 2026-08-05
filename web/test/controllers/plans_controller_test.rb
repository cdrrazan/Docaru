# frozen_string_literal: true

require "test_helper"

class PlansControllerTest < ActionDispatch::IntegrationTest
  test "pricing is public" do
    get plan_path

    assert_response :success
    assert_select "h1", "Pricing"
  end

  # The trust position depends on this being true and being said out loud.
  test "states that alerts are never paywalled" do
    get plan_path

    assert_select "p", /never paywalled/
  end

  test "shows the household its own plan when signed in" do
    sign_in_as users(:one)
    get plan_path

    assert_select "h2", text: "Your plan"
    assert_select "p", /household plan/
  end

  test "upgrading changes the limits" do
    sign_in_as users(:two) # free plan
    assert_equal 1, households(:two).member_limit

    patch plan_path

    assert_equal "household", households(:two).reload.plan
    assert_equal 6, households(:two).member_limit
  end

  test "upgrading requires an account" do
    patch plan_path

    assert_redirected_to new_session_path
  end
end
