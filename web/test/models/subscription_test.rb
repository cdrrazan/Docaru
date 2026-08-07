# frozen_string_literal: true

require "test_helper"

# Where money turns into entitlement. The failure that matters here is silent:
# a household that paid for one tier and is served another, or one demoted to
# free because a lookup missed.
class SubscriptionTest < ActiveSupport::TestCase
  setup { @household = households(:one) }

  def with_prices(household: "pri_household", archive: "pri_archive")
    originals = ENV.slice("PADDLE_PRICE_ID_HOUSEHOLD", "PADDLE_PRICE_ID_ARCHIVE", "PADDLE_PRICE_ID")
    ENV["PADDLE_PRICE_ID_HOUSEHOLD"] = household
    ENV["PADDLE_PRICE_ID_ARCHIVE"] = archive
    ENV.delete("PADDLE_PRICE_ID")
    yield
  ensure
    ENV.delete("PADDLE_PRICE_ID_HOUSEHOLD")
    ENV.delete("PADDLE_PRICE_ID_ARCHIVE")
    originals.each { |key, value| ENV[key] = value }
  end

  def subscription(price_id:, status: "active")
    Subscription.new(
      household: @household, paddle_subscription_id: "sub_#{price_id}",
      price_id: price_id, status: status
    )
  end

  test "puts a household on the plan the price it paid for names" do
    with_prices do
      subscription(price_id: "pri_archive").apply!

      assert_equal "archive", @household.reload.plan
    end
  end

  test "the household price buys the household plan" do
    with_prices do
      subscription(price_id: "pri_household").apply!

      assert_equal "household", @household.reload.plan
    end
  end

  # A retired price, or an instance reconfigured since the sale. Falling back to
  # the cheaper paid tier under-serves rather than over-charges, and — the part
  # that matters — never drops a paying customer to free over a lookup miss.
  test "an unrecognised price still buys a paid plan" do
    with_prices do
      subscription(price_id: "pri_from_last_year").apply!

      assert_equal "household", @household.reload.plan
    end
  end

  test "a subscription that has ended returns the household to free" do
    with_prices do
      @household.update!(plan: "archive")
      subscription(price_id: "pri_archive", status: "canceled").apply!

      assert_equal "free", @household.reload.plan
    end
  end

  # Paddle retries a failed card for days. Demoting on the first bounce takes
  # capacity from a household that is about to pay, and every alert keeps
  # working regardless — which is asserted here because it is the promise the
  # pricing page makes in writing.
  test "a troubled payment keeps both the plan and the alerts" do
    with_prices do
      %w[past_due paused].each do |status|
        subscription(price_id: "pri_archive", status: status).apply!

        assert_equal "archive", @household.reload.plan
        assert_predicate @household, :alerting?
      end
    end
  end

  test "sells only the plans this instance has a price for" do
    with_prices(archive: nil) do
      assert_equal [ "household" ], Paddle.sellable_plans
    end
  end

  # An instance configured before the archive tier existed sets PADDLE_PRICE_ID
  # and nothing else. It must keep working without being edited.
  test "the original single price id still names the household plan" do
    originals = ENV.slice("PADDLE_PRICE_ID_HOUSEHOLD", "PADDLE_PRICE_ID_ARCHIVE", "PADDLE_PRICE_ID")
    ENV.delete("PADDLE_PRICE_ID_HOUSEHOLD")
    ENV.delete("PADDLE_PRICE_ID_ARCHIVE")
    ENV["PADDLE_PRICE_ID"] = "pri_legacy"

    assert_equal "pri_legacy", Paddle.price_id("household")
    assert_equal "household", Paddle.plan_for_price("pri_legacy")
  ensure
    ENV.delete("PADDLE_PRICE_ID")
    originals.each { |key, value| ENV[key] = value }
  end
end
