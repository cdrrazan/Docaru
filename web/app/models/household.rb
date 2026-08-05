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

  validates :name, presence: true, length: { maximum: 120 }
  validates :plan, inclusion: { in: PLANS }

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
end
