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

  validates :name, presence: true, length: { maximum: 120 }
  validates :plan, inclusion: { in: PLANS }

  def document_limit = DOCUMENT_LIMITS.fetch(plan, 20)
  def member_limit = MEMBER_LIMITS.fetch(plan, 1)

  def documents_remaining = [ document_limit - documents.count, 0 ].max
  def members_remaining = [ member_limit - members.count, 0 ].max

  def can_add_document? = documents.count < document_limit
  def can_add_member? = members.count < member_limit

  # Deliberately not a limit check. Reminders are never gated by plan — a
  # household over its document limit still gets alerted about everything it
  # already has, because the alternative is letting somebody lose their visa
  # over a billing state.
  def alerting? = true
end
