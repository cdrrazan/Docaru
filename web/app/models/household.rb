# frozen_string_literal: true

class Household < ApplicationRecord
  PLANS = %w[free household self_hosted].freeze

  # Free tier caps documents rather than megabytes. A family hitting the cap is
  # the upgrade trigger, and counting documents is something a user can predict
  # — nobody knows how many megabytes a passport scan is.
  DOCUMENT_LIMITS = { "free" => 20, "household" => Float::INFINITY, "self_hosted" => Float::INFINITY }.freeze
  MEMBER_LIMITS = { "free" => 1, "household" => 6, "self_hosted" => Float::INFINITY }.freeze

  has_many :users, dependent: :destroy
  has_many :members, dependent: :destroy
  has_many :documents, through: :members
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

  def document_limit = DOCUMENT_LIMITS.fetch(plan, 20)
  def member_limit = MEMBER_LIMITS.fetch(plan, 1)

  def documents_remaining = [ document_limit - documents.count, 0 ].max
  def members_remaining = [ member_limit - members.count, 0 ].max

  def can_add_document? = documents.count < document_limit
  def can_add_member? = members.count < member_limit

  # Deliberately not a limit check, and deliberately not a billing check.
  # Reminders are never gated by plan — a household over its document limit, or
  # with a card that bounced this morning, still gets alerted about everything
  # it already has. Somebody whose card expires while they are abroad is exactly
  # the person most likely to need the alert.
  def alerting? = true

  # After a downgrade a household can be over its limit and stay there: nothing
  # is deleted and nothing stops being watched. What lapsing costs is the
  # ability to add more — capacity, not safety.
  def over_document_limit? = documents.count > document_limit
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
