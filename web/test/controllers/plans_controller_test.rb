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

  # The button opens a checkout; it does not grant anything. The plan moves when
  # Paddle says the money arrived, on the webhook — a browser that has been
  # redirected back is evidence of nothing.
  test "clicking upgrade never grants the plan by itself" do
    sign_in_as users(:two) # free plan

    patch plan_path

    assert_equal "free", households(:two).reload.plan
  end

  test "an instance with no billing configured says so instead of failing" do
    sign_in_as users(:two)

    patch plan_path

    assert_redirected_to plan_path
    follow_redirect!
    assert_select ".flash-alert", /not switched on/
  end

  # Entitlement is derived from the subscription, never assigned in two places.
  test "an active subscription is what grants the household plan" do
    households(:two).create_subscription!(paddle_subscription_id: "sub_1", status: "active").apply!

    assert_equal "household", households(:two).reload.plan
    assert_equal 6, households(:two).member_limit
  end

  test "the upgrade button is hidden when billing is not configured" do
    sign_in_as users(:two)
    get plan_path

    assert_select "input[value='Upgrade to the household plan']", false
    assert_select ".banner", /not switched on/
  end

  test "upgrading requires an account" do
    patch plan_path

    assert_redirected_to new_session_path
  end
end
