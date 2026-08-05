# frozen_string_literal: true

require "test_helper"

class PaddleWebhooksControllerTest < ActionDispatch::IntegrationTest
  SECRET = "pdl_ntfset_secret"

  setup do
    @original = ENV["PADDLE_WEBHOOK_SECRET"]
    ENV["PADDLE_WEBHOOK_SECRET"] = SECRET
    @household = households(:two) # starts on the free plan
  end

  teardown { ENV["PADDLE_WEBHOOK_SECRET"] = @original }

  def event(type: "subscription.activated", status: "active", id: "evt_#{SecureRandom.hex(4)}",
            occurred_at: Time.current, subscription_id: "sub_123", household: @household, canceled_at: nil)
    {
      event_id: id,
      event_type: type,
      occurred_at: occurred_at.utc.iso8601(3),
      data: {
        id: subscription_id,
        status: status,
        customer_id: "ctm_1",
        canceled_at: canceled_at,
        custom_data: { household_id: household.id.to_s },
        current_billing_period: { ends_at: 1.month.from_now.utc.iso8601 },
        items: [ { price: { id: "pri_1" } } ]
      }
    }.to_json
  end

  def deliver(payload, signature: nil, at: Time.current)
    ts = at.to_i
    signature ||= "ts=#{ts};h1=#{OpenSSL::HMAC.hexdigest("SHA256", SECRET, "#{ts}:#{payload}")}"

    post "/webhooks/paddle", params: payload, headers: {
      "Paddle-Signature" => signature, "Content-Type" => "application/json"
    }
  end

  test "an unsigned request changes nothing" do
    deliver(event, signature: "ts=1;h1=deadbeef")

    assert_response :unauthorized
    assert_equal "free", @household.reload.plan
  end

  test "a signed activation moves the household onto the paid plan" do
    deliver(event)

    assert_response :ok
    assert_equal "household", @household.reload.plan
    assert_equal "active", @household.subscription.status
  end

  # Paddle retries until it gets a 2xx, so the same event arriving twice is the
  # normal case rather than a fault.
  test "the same event twice is applied once" do
    payload = event

    deliver(payload)
    assert_difference -> { WebhookEvent.count }, 0 do
      deliver(payload)
    end

    assert_response :ok
    assert_equal 1, Subscription.where(household: @household).count
  end

  test "a cancellation returns the household to free" do
    deliver(event)
    deliver(event(type: "subscription.canceled", status: "canceled", occurred_at: 1.minute.from_now))

    assert_equal "free", @household.reload.plan
  end

  # Out-of-order delivery is how a cancellation from last week undoes today's
  # renewal, so a stale event must not overwrite a newer one.
  test "an event that arrives late does not undo a newer one" do
    deliver(event(type: "subscription.canceled", status: "canceled", occurred_at: 1.minute.ago))
    assert_equal "free", @household.reload.plan

    deliver(event(status: "active", occurred_at: Time.current))
    assert_equal "household", @household.reload.plan

    # The cancellation, redelivered, is older than what we now hold.
    deliver(event(type: "subscription.canceled", status: "canceled", occurred_at: 2.minutes.ago))

    assert_equal "household", @household.reload.plan, "a stale event reverted a newer one"
  end

  # Paddle retries a failed card for days. Demoting somebody the moment it
  # bounces takes capacity from a household that is about to pay.
  test "a failed payment keeps the household entitled" do
    deliver(event)
    deliver(event(type: "subscription.past_due", status: "past_due", occurred_at: 1.minute.from_now))

    assert_equal "household", @household.reload.plan
    assert_predicate @household.subscription, :troubled?
  end

  # The promise the pricing page makes, as a test: nobody misses a visa deadline
  # over a card.
  test "no billing state ever stops a reminder" do
    %w[active past_due paused canceled].each_with_index do |status, index|
      deliver(event(status: status, occurred_at: (index + 1).minutes.from_now))

      assert_predicate @household.reload, :alerting?, "reminders stopped while #{status}"
    end
  end

  test "an unknown event type is recorded and ignored" do
    deliver(event(type: "report.created", status: "whatever"))

    assert_response :ok
    assert_equal "free", @household.reload.plan
    assert WebhookEvent.exists?(event_type: "report.created")
  end

  test "malformed json is rejected rather than raising" do
    deliver("not json at all")

    assert_response :bad_request
  end

  # custom_data is set when the checkout is created and comes back on every
  # event, so the household is never inferred from anything a browser said.
  test "an event for an unknown household is ignored" do
    payload = event.sub(/"household_id":"\d+"/, '"household_id":"999999"')
    deliver(payload)

    assert_response :ok
    assert_equal 0, Subscription.count
  end
end
