# frozen_string_literal: true

require "test_helper"

class DeliverPushJobTest < ActiveJob::TestCase
  include Rails.application.routes.url_helpers

  setup do
    @document = documents(:passport)
    @subscription = users(:one).push_subscriptions.create!(
      endpoint: "https://push.example.com/one", p256dh_key: "pub", auth_key: "auth"
    )
  end

  test "does nothing at all when no keys are configured" do
    with_vapid(nil, nil) do
      assert_nothing_raised { DeliverPushJob.perform_now(@document, "start_now", "act") }
    end
  end

  test "pushes to every device in the household" do
    delivered = []
    stub_delivery(delivered) do
      DeliverPushJob.perform_now(@document, "start_now", "act")
    end

    assert_equal 1, delivered.size
    assert_match(/Start renewing/, delivered.first[:title])
    assert_equal document_path(@document), delivered.first[:path]
  end

  test "skips devices the push service has disowned" do
    @subscription.expire!
    delivered = []

    stub_delivery(delivered) { DeliverPushJob.perform_now(@document, "start_now", "act") }

    assert_empty delivered
  end

  # One unreachable push service must not stop the others, for the same reason
  # one malformed document must not stop the nightly sweep.
  test "one failing device does not stop the rest" do
    users(:one).push_subscriptions.create!(
      endpoint: "https://push.example.com/two", p256dh_key: "pub", auth_key: "auth"
    )

    delivered = []
    PushSubscription.class_eval do
      define_method(:deliver) do |**args|
        raise "unreachable" if endpoint.end_with?("one")

        delivered << args
        true
      end
    end

    with_vapid("pub", "priv") do
      assert_nothing_raised { DeliverPushJob.perform_now(@document, "start_now", "act") }
    end

    assert_equal 1, delivered.size
  ensure
    PushSubscription.remove_method(:deliver)
  end

  # Push and email are the same message by two routes. A household reading
  # "start today" on a phone and "in a month" in an inbox would trust neither.
  test "says exactly what the email subject says" do
    mail = ReminderMailer.with(user: users(:one), document: @document, kind: "start_now", urgency: "act").deadline

    assert_equal mail.subject, ReminderNotification.title(@document, "act")
  end

  private

  def stub_delivery(collector)
    PushSubscription.class_eval do
      define_method(:deliver) do |**args|
        collector << args
        true
      end
    end

    with_vapid("pub", "priv") { yield }
  ensure
    PushSubscription.remove_method(:deliver)
  end

  def with_vapid(public_key, private_key)
    originals = ENV.values_at("VAPID_PUBLIC_KEY", "VAPID_PRIVATE_KEY")
    ENV["VAPID_PUBLIC_KEY"] = public_key
    ENV["VAPID_PRIVATE_KEY"] = private_key
    yield
  ensure
    ENV["VAPID_PUBLIC_KEY"], ENV["VAPID_PRIVATE_KEY"] = originals
  end
end
