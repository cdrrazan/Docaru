# frozen_string_literal: true

require "net/http"

# The whole surface Paddle presents to this application: verify a webhook, and
# open a checkout.
#
# Paddle rather than Stripe because Stripe will not onboard a business based in
# Nepal. Paddle is a Merchant of Record, which means it is the seller: it
# collects and remits VAT and sales tax in every jurisdiction the buyer might be
# in, which for a product sold to migrants scattered across a dozen countries is
# the difference between shipping and registering for tax in each of them.
#
# No gem and no Paddle.js. The API is JSON over HTTPS and the signature is an
# HMAC, both of which the standard library does; and a checkout opened by
# redirect rather than by an overlay keeps a third-party script off every page,
# which is the same reason the playbooks are server-rendered.
module Paddle
  class Error < StandardError; end
  class NotConfigured < Error; end

  # Paddle signs with `ts=<unix>;h1=<hmac>` over "<ts>:<raw body>".
  SIGNATURE = /\Ats=(?<ts>\d+);h1=(?<hmac>[a-f0-9]+)\z/

  # Anything older is a replay. Generous enough to survive a slow queue, short
  # enough that a captured request stops working the same day.
  TOLERANCE = 5.minutes

  class << self
    def api_key = ENV["PADDLE_API_KEY"].presence
    def webhook_secret = ENV["PADDLE_WEBHOOK_SECRET"].presence
    def price_id = ENV["PADDLE_PRICE_ID"].presence

    # Sandbox by default. Getting this backwards means either taking real money
    # in a test or silently taking none in production; defaulting to the one
    # that cannot charge anybody is the safer mistake.
    def sandbox? = ENV.fetch("PADDLE_ENVIRONMENT", "sandbox") != "production"

    def host = sandbox? ? "sandbox-api.paddle.com" : "api.paddle.com"

    # The upgrade button only appears when all three are present. A checkout
    # that fails after the click is worse than one that was never offered.
    def configured? = api_key.present? && webhook_secret.present? && price_id.present?

    # Constant-time comparison, and the timestamp is part of what is signed —
    # otherwise a captured payload could be replayed forever.
    def verify(payload:, signature:, now: Time.current)
      return false unless webhook_secret

      match = SIGNATURE.match(signature.to_s)
      return false unless match

      timestamp = Time.at(match[:ts].to_i).utc
      return false if (now - timestamp).abs > TOLERANCE

      expected = OpenSSL::HMAC.hexdigest("SHA256", webhook_secret, "#{match[:ts]}:#{payload}")
      ActiveSupport::SecurityUtils.secure_compare(expected, match[:hmac])
    end

    # A transaction is a checkout that has not happened yet. Paddle hands back a
    # URL to send the buyer to, which is why no script of theirs has to run here.
    def create_checkout(household:, email:, success_url:)
      raise NotConfigured unless configured?

      response = post("/transactions", {
        items: [ { price_id: price_id, quantity: 1 } ],
        customer: { email: email },
        # Comes back on every webhook for this subscription, so the household
        # can be found without trusting anything the browser said.
        custom_data: { household_id: household.id.to_s },
        checkout: { url: success_url }
      })

      response.dig("data", "checkout", "url") or
        raise Error, "Paddle returned no checkout url: #{response.inspect}"
    end

    private

    def post(path, body)
      uri = URI::HTTPS.build(host: host, path: "/#{path.delete_prefix("/")}")

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      request.body = body.to_json

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) do |http|
        http.request(request)
      end

      raise Error, "Paddle #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end
end
