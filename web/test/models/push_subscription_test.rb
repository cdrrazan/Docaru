# frozen_string_literal: true

require "test_helper"

class PushSubscriptionTest < ActiveSupport::TestCase
  def build(**overrides)
    users(:one).push_subscriptions.build({
      endpoint: "https://push.example.com/#{SecureRandom.hex(8)}",
      p256dh_key: "key", auth_key: "auth"
    }.merge(overrides))
  end

  test "requires an https endpoint" do
    assert_predicate build, :valid?
    assert_not_predicate build(endpoint: "http://push.example.com/x"), :valid?
    assert_not_predicate build(endpoint: ""), :valid?
  end

  # The endpoint is handed straight to an HTTP client, so anchoring only the
  # start would accept a trailing newline and whatever followed it.
  test "rejects anything smuggled after the url" do
    assert_not_predicate build(endpoint: "https://push.example.com/x\nHost: elsewhere"), :valid?
    assert_not_predicate build(endpoint: "https://push.example.com/x junk"), :valid?
  end

  # One row per browser per device: the same person on a phone and a laptop is
  # two subscriptions, and both should be reminded.
  test "the endpoint identifies a device within a user" do
    endpoint = "https://push.example.com/same"
    build(endpoint: endpoint).save!

    assert_not_predicate build(endpoint: endpoint), :valid?
    assert_predicate users(:two).push_subscriptions.build(endpoint: endpoint, p256dh_key: "k", auth_key: "a"), :valid?
  end

  test "active excludes the ones the push service has disowned" do
    live = build.tap(&:save!)
    dead = build.tap(&:save!)
    dead.expire!

    assert_includes PushSubscription.active, live
    assert_not_includes PushSubscription.active, dead
  end

  # No keys configured is the normal state for a self-hosted instance that has
  # not set them up, and it must be silent rather than an exception on every
  # nightly sweep.
  test "delivery is a no-op rather than an error when unconfigured" do
    subscription = build.tap(&:save!)

    with_env("VAPID_PUBLIC_KEY" => nil, "VAPID_PRIVATE_KEY" => nil) do
      assert_not PushSubscription.configured?
      assert_not subscription.deliver(title: "t", body: "b", path: "/")
    end
  end

  test "configured once both halves of the pair are present" do
    with_env("VAPID_PUBLIC_KEY" => "pub", "VAPID_PRIVATE_KEY" => nil) do
      assert_not PushSubscription.configured?
    end

    with_env("VAPID_PUBLIC_KEY" => "pub", "VAPID_PRIVATE_KEY" => "priv") do
      assert PushSubscription.configured?
      assert_equal "pub", PushSubscription.vapid[:public_key]
    end
  end

  private

  def with_env(values)
    original = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| ENV[key] = value }
  end
end
