# frozen_string_literal: true

# What Paddle believes about a household's billing, and what this application
# does about it.
#
# The policy the pricing page already promises, encoded rather than intended:
# **a billing state never stops a reminder.** Somebody whose card expires while
# they are abroad is exactly the person most likely to need the alert, and
# taking it away would be the product failing at the only job it has. What
# lapsing costs is the ability to add *more* people and documents — capacity,
# not safety.
class Subscription < ApplicationRecord
  belongs_to :household

  # Paddle's vocabulary, stored verbatim rather than translated at the boundary.
  # A status we have never seen must not be silently mapped onto one we have.
  ENTITLED = %w[active trialing past_due paused].freeze
  ENDED = %w[canceled].freeze

  validates :paddle_subscription_id, presence: true, uniqueness: true
  validates :status, presence: true

  # past_due and paused are deliberately entitled. Paddle retries a failed
  # payment for days before giving up, and demoting somebody the moment a card
  # bounces would take capacity away from a household that is about to pay.
  def entitled? = ENTITLED.include?(status)
  def ended? = ENDED.include?(status)
  def troubled? = status.in?(%w[past_due paused])

  # The plan is derived, never assigned from two places. Anything else drifts:
  # a household ends up on the household plan with no subscription, or the
  # reverse, and only one of those is discovered by a customer.
  def apply!
    household.update!(plan: entitled? ? "household" : "free")
  end

  # Webhooks arrive out of order as a matter of course. An older event must not
  # be allowed to overwrite what a newer one already said — that is how a
  # cancellation from last week undoes today's renewal.
  def stale?(occurred_at)
    last_event_at.present? && occurred_at.present? && occurred_at < last_event_at
  end
end
