# frozen_string_literal: true

# Paddle telling us what it just did.
#
# This is the only thing that changes a household's plan. The browser is never
# believed about billing — it can be told a checkout succeeded, but the record
# moves when Paddle says so and not before.
class PaddleWebhooksController < ActionController::API
  # Handled statuses, and what each one means for entitlement. Anything not
  # listed is recorded and ignored rather than guessed at.
  HANDLED = %w[
    subscription.created subscription.updated subscription.activated
    subscription.canceled subscription.paused subscription.resumed
    subscription.past_due transaction.completed
  ].freeze

  def create
    payload = request.raw_post

    unless Paddle.verify(payload: payload, signature: request.headers["Paddle-Signature"])
      return head :unauthorized
    end

    event = JSON.parse(payload)

    # Recorded before it is acted on, so a retry of something we already applied
    # is a no-op rather than a second application of it.
    return head :ok unless first_time?(event)

    apply(event) if event["event_type"].in?(HANDLED)

    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private

  def first_time?(event)
    WebhookEvent.create!(
      provider: "paddle",
      event_id: event["event_id"],
      event_type: event["event_type"],
      occurred_at: event["occurred_at"]
    )
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  def apply(event)
    data = event["data"] || {}
    household = find_household(data)
    return unless household

    occurred_at = Time.zone.parse(event["occurred_at"].to_s)
    subscription = Subscription.find_or_initialize_by(household: household)

    # An older event must not overwrite what a newer one already said. Out-of-
    # order delivery is how a cancellation from last week undoes today's renewal.
    return if subscription.persisted? && subscription.stale?(occurred_at)

    subscription.assign_attributes(
      paddle_subscription_id: data["id"] || data["subscription_id"],
      paddle_customer_id: data["customer_id"],
      price_id: data.dig("items", 0, "price", "id"),
      status: data["status"].presence || subscription.status,
      renews_on: parse_date(data.dig("current_billing_period", "ends_at")),
      last_event_at: occurred_at
    )
    # Only when present: an update that says nothing about cancellation must not
    # be read as un-cancelling.
    subscription.canceled_at = Time.zone.parse(data["canceled_at"].to_s) if data["canceled_at"].present?

    return unless subscription.paddle_subscription_id && subscription.status

    subscription.save!
    subscription.apply!
  end

  # custom_data is set when the checkout is created and comes back on every
  # event for that subscription, so the household never has to be inferred from
  # an email address somebody could have typed.
  def find_household(data)
    id = data.dig("custom_data", "household_id")
    return Household.find_by(id: id) if id.present?

    Subscription.find_by(paddle_subscription_id: data["id"] || data["subscription_id"])&.household
  end

  def parse_date(value) = value.present? ? Time.zone.parse(value.to_s)&.to_date : nil
end
