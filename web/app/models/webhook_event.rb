# frozen_string_literal: true

# Every webhook we have already seen.
#
# Paddle retries until it gets a 2xx, so the same event arriving more than once
# is the normal case rather than a fault. The unique index is what makes
# handling idempotent; this model exists mostly to give that index a name.
class WebhookEvent < ApplicationRecord
  validates :provider, :event_id, :event_type, presence: true
end
