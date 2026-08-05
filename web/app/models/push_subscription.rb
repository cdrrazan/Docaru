# frozen_string_literal: true

# One browser on one device that has agreed to be interrupted.
#
# Push exists because email alone is a weak channel for this product: a reminder
# competes with everything else in an inbox, and the whole thesis is that the
# alert has to land while there is still time to act on it. It is additive —
# email is always sent, so an instance with no VAPID keys, or a household that
# declines the permission prompt, loses nothing it had before.
class PushSubscription < ApplicationRecord
  belongs_to :user

  # Anchored at both ends and closed to whitespace. This string is handed
  # straight to an HTTP client, so an unanchored pattern would accept a trailing
  # newline and whatever a caller chose to put after it.
  ENDPOINT = %r{\Ahttps://[^\s]+\z}

  validates :endpoint, presence: true, length: { maximum: 512 },
                       uniqueness: { scope: :user_id },
                       format: { with: ENDPOINT, message: "must be an https endpoint" }
  validates :p256dh_key, :auth_key, presence: true

  scope :active, -> { where(expired_at: nil) }

  # Configured from the environment rather than credentials, for the same reason
  # the encryption keys are: somebody self-hosting supplies their own and cannot
  # decrypt this repository's credentials file anyway.
  def self.vapid
    public_key = ENV["VAPID_PUBLIC_KEY"].presence
    private_key = ENV["VAPID_PRIVATE_KEY"].presence
    return nil unless public_key && private_key

    { public_key:, private_key:, subject: ENV.fetch("VAPID_SUBJECT", "mailto:#{ENV.fetch("MAIL_FROM", "reminders@example.com")}") }
  end

  def self.configured? = vapid.present?

  # True when the push service says this subscription is gone for good. The
  # browser was uninstalled, the permission revoked, or the device reset —
  # all of which are permanent, unlike a timeout.
  GONE = [ 404, 410 ].freeze

  def deliver(title:, body:, path:)
    vapid = self.class.vapid
    return false unless vapid

    WebPush.payload_send(
      message: { title:, options: { body:, data: { path: }, tag: "renewal-#{path}" } }.to_json,
      endpoint: endpoint,
      p256dh: p256dh_key,
      auth: auth_key,
      vapid: vapid,
      urgency: "normal"
    )
    true
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
    expire!
    false
  rescue WebPush::ResponseError => e
    GONE.include?(e.response&.code.to_i) ? expire! : raise
    false
  end

  def expire!
    update_column(:expired_at, Time.current)
  end
end
