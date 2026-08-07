# frozen_string_literal: true

class Household < ApplicationRecord
  PLANS = %w[free household archive self_hosted].freeze

  # Capacity is bytes, not documents.
  #
  # It used to be documents, on the reasoning that a count is something a person
  # can predict and megabytes are not. True, and beside the point: storage is
  # what a hosted instance actually pays for, and the two numbers had drifted
  # far enough apart to matter. Twenty documents was the free cap while a single
  # document could carry a hundred pages at ten megabytes each — a free tier
  # whose real ceiling was around twenty gigabytes, and a pricing page claiming
  # to limit storage while limiting something else entirely.
  #
  # The predictability objection is answered by the interface rather than by the
  # unit: a used-of-total bar, and the count of typical scans that fits. That is
  # how every cloud drive solves it, because it works.
  STORAGE_LIMITS = {
    "free" => 1.gigabyte,
    "household" => 25.gigabytes,
    "archive" => 100.gigabytes,
    "self_hosted" => Float::INFINITY
  }.freeze

  MEMBER_LIMITS = {
    "free" => 1,
    "household" => 6,
    "archive" => 6,
    "self_hosted" => Float::INFINITY
  }.freeze

  # Roughly what a scan costs after the browser has resized and re-encoded it.
  # Used only to turn bytes into a sentence a person can act on.
  TYPICAL_SCAN_BYTES = 250.kilobytes

  has_many :users, dependent: :destroy
  has_many :members, dependent: :destroy
  has_many :documents, through: :members
  has_many :attachments, through: :documents
  has_one :subscription, dependent: :destroy

  has_secure_token :vault_salt, length: 24
  has_secure_token :recovery_salt, length: 24

  validates :name, presence: true, length: { maximum: 120 }
  validates :plan, inclusion: { in: PLANS }

  # The wrapped keys are opaque to this application, but "opaque" is not "any
  # string at all" — they are base64 of a 32-byte key plus a GCM tag, so a
  # length bound and an alphabet keep a malformed or oversized write out of a
  # column nothing server-side will ever parse and reject later.
  BASE64 = %r{\A[A-Za-z0-9+/=]+\z}
  NONCE = %r{\A[A-Za-z0-9+/=]{12,32}\z}

  validates :wrapped_key, :recovery_wrapped_key,
            format: { with: BASE64, message: "is not valid base64" },
            length: { maximum: 512 }, allow_nil: true
  validates :wrapped_key_iv, :recovery_wrapped_key_iv,
            format: { with: NONCE, message: "is not a valid nonce" }, allow_nil: true

  def storage_limit = STORAGE_LIMITS.fetch(plan, STORAGE_LIMITS.fetch("free"))
  def member_limit = MEMBER_LIMITS.fetch(plan, 1)

  # Summed rather than counted from a column kept up to date by callbacks. A
  # denormalised total that drifts is worse than one query per page: it either
  # bills somebody for space they are not using or lets them past a limit they
  # have already passed, and both are discovered late.
  def storage_used = attachments.sum(:byte_size)

  def storage_remaining = [ storage_limit - storage_used, 0 ].max

  # Nil when unlimited, so a view can ask for the bar and get told there is
  # nothing to draw rather than dividing by infinity.
  def storage_fraction
    return nil if storage_limit.infinite?

    [ storage_used.to_f / storage_limit, 1.0 ].min
  end

  # Asked before an upload, with the size of what is about to arrive. Checked
  # server-side because the browser reports its own byte count.
  def can_store?(bytes) = storage_used + bytes.to_i <= storage_limit

  def storage_exhausted? = storage_remaining.zero?

  # "About 400 more scans" is a number somebody can act on; "738 MB remaining"
  # is one they have to translate first.
  def scans_remaining
    return nil if storage_limit.infinite?

    (storage_remaining / TYPICAL_SCAN_BYTES).floor
  end

  def members_remaining = [ member_limit - members.count, 0 ].max

  def can_add_member? = members.count < member_limit

  # Deliberately not a limit check, and deliberately not a billing check.
  # Reminders are never gated by plan — a household over its document limit, or
  # with a card that bounced this morning, still gets alerted about everything
  # it already has. Somebody whose card expires while they are abroad is exactly
  # the person most likely to need the alert.
  def alerting? = true

  # After a downgrade a household can be over its limit and stay there: nothing
  # is deleted and nothing stops being watched. What lapsing costs is the
  # ability to add more — capacity, not safety. Deleting somebody's birth
  # certificate because a card expired would be theft dressed as billing.
  def over_storage_limit? = storage_used > storage_limit
  def over_member_limit? = members.count > member_limit

  # Generated lazily so existing households pick one up on first vault use.
  # Not a secret: its job is to stop one precomputed attack from working
  # against every household at once.
  def vault_salt!
    regenerate_vault_salt if vault_salt.blank?
    vault_salt
  end

  def recovery_salt!
    regenerate_recovery_salt if recovery_salt.blank?
    recovery_salt
  end

  # Whether a vault key exists yet. Until it does the browser has nothing to
  # unwrap, so the vault asks to be set up rather than asking to be unlocked —
  # a distinction worth making, because "wrong passphrase" and "you have not
  # chosen one yet" are very different things to be told.
  def vault_initialised? = wrapped_key.present?

  def recovery_available? = recovery_wrapped_key.present?

  # Both wrappings of the same key, and nothing else. Named to make the reviews
  # easy: if anything ever reads these server-side for a purpose other than
  # handing them back to the browser, that is the bug.
  def store_vault_key!(wrapped:, wrapped_iv:, recovery_wrapped:, recovery_wrapped_iv:)
    update!(
      wrapped_key: wrapped,
      wrapped_key_iv: wrapped_iv,
      recovery_wrapped_key: recovery_wrapped,
      recovery_wrapped_key_iv: recovery_wrapped_iv,
      recovery_used_at: nil
    )
  end

  # Recovery, or a plain passphrase change: the vault key is unchanged, so the
  # scans are untouched and only its passphrase wrapping is replaced. The
  # recovery wrapping is replaced at the same time, because a code that has been
  # used to get back in has been written down somewhere, read aloud to support,
  # or sitting in a screenshot — spent, either way.
  def rewrap_vault_key!(wrapped:, wrapped_iv:, recovery_wrapped:, recovery_wrapped_iv:)
    update!(
      wrapped_key: wrapped,
      wrapped_key_iv: wrapped_iv,
      recovery_wrapped_key: recovery_wrapped,
      recovery_wrapped_key_iv: recovery_wrapped_iv,
      recovery_used_at: Time.current
    )
  end
end
