# frozen_string_literal: true

require "test_helper"

class DeliverPushJobTest < ActiveJob::TestCase
  include Rails.application.routes.url_helpers

  # WebPush::ResponseError reads body and code off the response in its own
  # constructor, so a nil will not stand in for one.
  Rejection = Struct.new(:code, :body)

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
    sent = capture_pushes { DeliverPushJob.perform_now(@document, "start_now", "act") }

    assert_equal 1, sent.size
    assert_equal [ "https://push.example.com/one" ], sent.map { |push| push[:endpoint] }

    message = JSON.parse(sent.first[:message])

    assert_match(/Start renewing/, message["title"])
    assert_equal document_path(@document), message.dig("options", "data", "path")
  end

  test "skips devices the push service has disowned" do
    @subscription.expire!

    assert_empty capture_pushes { DeliverPushJob.perform_now(@document, "start_now", "act") }
  end

  # One unreachable push service must not stop the others, for the same reason
  # one malformed document must not stop the nightly sweep.
  test "one failing device does not stop the rest" do
    users(:one).push_subscriptions.create!(
      endpoint: "https://push.example.com/two", p256dh_key: "pub", auth_key: "auth"
    )

    sent = capture_pushes(failing: "https://push.example.com/one") do
      assert_nothing_raised { DeliverPushJob.perform_now(@document, "start_now", "act") }
    end

    assert_equal [ "https://push.example.com/two" ], sent.map { |push| push[:endpoint] }
  end

  # A push service reporting 410 means gone for good, not a timeout. Retrying
  # those forever helps nobody.
  test "a subscription the push service has disowned is marked expired" do
    gone = ->(**) { raise WebPush::ExpiredSubscription.new(Rejection.new("410", ""), "push.example.com") }

    with_vapid("pub", "priv") do
      stub_web_push(gone) { DeliverPushJob.perform_now(@document, "start_now", "act") }
    end

    assert_not_nil @subscription.reload.expired_at
    assert_empty PushSubscription.active
  end

  # Push and email are the same message by two routes. A household reading
  # "start today" on a phone and "in a month" in an inbox would trust neither.
  test "says exactly what the email subject says" do
    mail = ReminderMailer.with(user: users(:one), document: @document, kind: "start_now", urgency: "act").deadline

    assert_equal mail.subject, ReminderNotification.title(@document, "act")
  end

  private

  # Stubs WebPush itself rather than PushSubscription#deliver. Overriding a
  # method on the model and removing it afterwards deletes the real one too,
  # which silently breaks whatever runs next in the same process — a mistake
  # this file made once already.
  #
  # Hand-rolled because minitest 6 no longer ships mock, and the original is
  # restored rather than removed for exactly the reason above.
  def stub_web_push(replacement)
    singleton = WebPush.singleton_class
    singleton.alias_method(:payload_send_without_stub, :payload_send)
    singleton.define_method(:payload_send) { |**args| replacement.call(**args) }
    yield
  ensure
    singleton.alias_method(:payload_send, :payload_send_without_stub)
    singleton.remove_method(:payload_send_without_stub)
  end

  def capture_pushes(failing: nil)
    sent = []

    replacement = lambda do |**args|
      raise WebPush::ResponseError.new(Rejection.new("500", ""), "push.example.com") if args[:endpoint] == failing

      sent << args
      true
    end

    with_vapid("pub", "priv") { stub_web_push(replacement) { yield } }

    sent
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
