# frozen_string_literal: true

require "test_helper"

class PushSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  ENDPOINT = "https://push.example.com/abc123"

  def params(endpoint: ENDPOINT) = { endpoint: endpoint, p256dh_key: "pub", auth_key: "auth" }

  test "requires authentication" do
    sign_out
    post push_subscription_path, params: params

    assert_response :redirect
  end

  test "registers a device" do
    assert_difference -> { users(:one).push_subscriptions.count }, 1 do
      post push_subscription_path, params: params
    end

    assert_response :created
  end

  # The browser re-subscribes on its own whenever the push service rotates a
  # key, and sends the same endpoint back. That is the same device, not a new
  # one — otherwise every rotation doubles the notifications.
  test "re-registering the same endpoint updates rather than duplicates" do
    post push_subscription_path, params: params

    assert_no_difference -> { users(:one).push_subscriptions.count } do
      post push_subscription_path, params: params.merge(p256dh_key: "rotated")
    end

    assert_equal "rotated", users(:one).push_subscriptions.sole.p256dh_key
  end

  test "re-registering revives a subscription the push service had disowned" do
    post push_subscription_path, params: params
    users(:one).push_subscriptions.sole.expire!

    post push_subscription_path, params: params

    assert_nil users(:one).push_subscriptions.sole.expired_at
  end

  test "rejects an endpoint that is not https" do
    post push_subscription_path, params: params(endpoint: "http://push.example.com/x")

    assert_response :unprocessable_entity
  end

  test "revokes a device" do
    post push_subscription_path, params: params

    assert_difference -> { users(:one).push_subscriptions.count }, -1 do
      delete push_subscription_path, params: { endpoint: ENDPOINT }
    end
  end

  # A permission granted on one person's phone is theirs. Somebody else in the
  # household must not be able to revoke it or discover that it exists.
  test "one user cannot revoke another's device" do
    users(:two).push_subscriptions.create!(endpoint: ENDPOINT, p256dh_key: "k", auth_key: "a")

    assert_no_difference -> { users(:two).push_subscriptions.count } do
      delete push_subscription_path, params: { endpoint: ENDPOINT }
    end
  end
end
