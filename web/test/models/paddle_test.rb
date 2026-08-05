# frozen_string_literal: true

require "test_helper"

class PaddleTest < ActiveSupport::TestCase
  SECRET = "pdl_ntfset_secret"

  def sign(payload, at: Time.current, secret: SECRET)
    ts = at.to_i
    hmac = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{ts}:#{payload}")
    "ts=#{ts};h1=#{hmac}"
  end

  def with_secret(value = SECRET)
    original = ENV["PADDLE_WEBHOOK_SECRET"]
    ENV["PADDLE_WEBHOOK_SECRET"] = value
    yield
  ensure
    ENV["PADDLE_WEBHOOK_SECRET"] = original
  end

  test "accepts a correctly signed payload" do
    with_secret do
      payload = '{"event_id":"evt_1"}'

      assert Paddle.verify(payload: payload, signature: sign(payload))
    end
  end

  test "rejects a payload that has been altered" do
    with_secret do
      signature = sign('{"amount":"400"}')

      assert_not Paddle.verify(payload: '{"amount":"1"}', signature: signature)
    end
  end

  test "rejects a signature made with another secret" do
    with_secret do
      payload = '{"event_id":"evt_1"}'

      assert_not Paddle.verify(payload: payload, signature: sign(payload, secret: "wrong"))
    end
  end

  # The timestamp is inside what is signed, so a captured request stops working
  # rather than replaying forever.
  test "rejects a replay of an old request" do
    with_secret do
      payload = '{"event_id":"evt_1"}'
      old = sign(payload, at: 1.hour.ago)

      assert_not Paddle.verify(payload: payload, signature: old)
    end
  end

  test "rejects a timestamp from the future" do
    with_secret do
      payload = '{"event_id":"evt_1"}'

      assert_not Paddle.verify(payload: payload, signature: sign(payload, at: 1.hour.from_now))
    end
  end

  test "rejects malformed and missing signatures" do
    with_secret do
      payload = "{}"

      assert_not Paddle.verify(payload: payload, signature: nil)
      assert_not Paddle.verify(payload: payload, signature: "garbage")
      assert_not Paddle.verify(payload: payload, signature: "ts=abc;h1=def")
    end
  end

  # An instance with no secret must refuse everything rather than accept
  # anything, which is what a nil secret would do to a naive comparison.
  test "verifies nothing when unconfigured" do
    with_secret(nil) do
      payload = "{}"

      assert_not Paddle.verify(payload: payload, signature: sign(payload))
    end
  end

  # Getting this backwards means either taking real money in a test or silently
  # taking none in production.
  test "defaults to the sandbox" do
    original = ENV["PADDLE_ENVIRONMENT"]
    ENV.delete("PADDLE_ENVIRONMENT")

    assert_predicate Paddle, :sandbox?
    assert_equal "sandbox-api.paddle.com", Paddle.host

    ENV["PADDLE_ENVIRONMENT"] = "production"

    assert_not Paddle.sandbox?
    assert_equal "api.paddle.com", Paddle.host
  ensure
    ENV["PADDLE_ENVIRONMENT"] = original
  end
end
