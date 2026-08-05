# frozen_string_literal: true

# One dated obligation. The row itself is unremarkable; what makes it useful is
# that it can be joined to a renewal rule, which is what turns an expiry date
# into a date to start.
class Document < ApplicationRecord
  belongs_to :member
  has_one :household, through: :member
  has_many :reminders, dependent: :destroy

  # Renewing means a new expiry date, which means a new cycle. Clearing the sent
  # log lets the whole cascade run again for the new date instead of being
  # suppressed by last cycle's dedupe keys.
  after_update_commit :reset_reminders, if: :saved_change_to_expires_on?

  # Not needed to compute a date, so the server has no business reading them.
  encrypts :identifier
  encrypts :notes

  validates :kind, presence: true
  validates :issuing_country, presence: true, format: { with: /\A[A-Z]{2}\z/, message: "must be a two-letter country code" }
  validates :applying_from, format: { with: /\A([A-Z]{2}|domestic)\z/ }, allow_blank: true
  validates :expires_on, presence: true
  validates :label, length: { maximum: 120 }, allow_blank: true

  normalizes :issuing_country, with: ->(value) { value.to_s.strip.upcase }
  normalizes :applying_from, with: ->(value) { value.to_s.strip.presence&.then { |v| v == "domestic" ? v : v.upcase } }

  scope :expiring_first, -> { order(:expires_on) }

  def context = applying_from.presence || Renewaru::Rule::Context::DOMESTIC

  # Nil when the dataset has no rule for this country and kind. That is a real
  # and permanent state — the dataset is deliberately incomplete — so every
  # caller has to cope with it rather than assume a rule exists.
  def rule = @rule ||= RuleCatalog.find(issuing_country, kind)

  def resolved
    return nil unless rule

    @resolved ||= rule.resolve(RuleCatalog.normalise_context(rule, context))
  end

  def timeline = resolved&.timeline

  def title
    label.presence || rule&.title || kind.to_s.tr("_", " ").capitalize
  end

  # The whole point of the record.
  def start_by
    return nil unless timeline

    expires_on - timeline.start_days_before_expiry
  end

  def days_until_start
    start_by && (start_by - Date.current).to_i
  end

  def days_until_expiry = (expires_on - Date.current).to_i

  def expired? = days_until_expiry.negative?
  def feasible? = timeline.nil? || timeline.feasible?

  # Mirrors RenewalCalculation#status so the dashboard and the public
  # calculator can never disagree about how much trouble somebody is in.
  def status
    return :unknown unless timeline
    return :expired if expired?
    return :impossible unless timeline.feasible?
    return :overdue if days_until_start.negative?
    return :now if days_until_start <= 30

    :ahead
  end

  # Sorts the dashboard. Trouble first, then by how soon action is needed —
  # the product is a queue of what to do next, not a filing cabinet.
  SEVERITY = { expired: 0, overdue: 1, impossible: 2, now: 3, ahead: 4, unknown: 5 }.freeze

  def severity = SEVERITY.fetch(status, 5)

  # Deliberately a sort key rather than <=> plus Comparable. Comparable defines
  # ==, which would replace ActiveRecord's identity comparison and blow up on
  # any comparison against nil or a non-Document — including the ones Rails
  # makes internally.
  def sort_key = [ severity, start_by || expires_on ]

  def schedule = ReminderSchedule.new(self)
  def chain = PrerequisiteChain.new(self)

  private

  def reset_reminders
    reminders.delete_all
  end
end
