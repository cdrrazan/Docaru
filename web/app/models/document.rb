# frozen_string_literal: true

# Something a household holds and may need to reach.
#
# Most documents worth keeping never expire — a degree certificate, a birth
# certificate, a property deed. Those are the reason the vault exists: they sit
# in a drawer thirty kilometres away, and the moment somebody needs one they
# cannot get it. Storing them is the job.
#
# Some of them *do* expire, and for those this can also say when to start
# renewing, by joining the row to a public renewal rule. That is the layer on
# top — the reason to choose this over a synced folder — not the price of
# admission. A document with no expiry date is a first-class document.
class Document < ApplicationRecord
  belongs_to :member
  has_one :household, through: :member
  has_many :reminders, dependent: :destroy
  has_many :attachments, dependent: :destroy

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
  validates :label, length: { maximum: 120 }, allow_blank: true

  normalizes :issuing_country, with: ->(value) { value.to_s.strip.upcase }
  normalizes :applying_from, with: ->(value) { value.to_s.strip.presence&.then { |v| v == "domestic" ? v : v.upcase } }

  scope :expiring_first, -> { order(:expires_on) }
  scope :dated, -> { where.not(expires_on: nil) }
  scope :undated, -> { where(expires_on: nil) }
  scope :recently_added, -> { order(created_at: :desc) }

  # Free-text search across the fields the server can actually read. `identifier`
  # and `notes` are encrypted precisely so the server cannot, which means a
  # passport number is not searchable — the right trade, and one worth stating
  # rather than quietly failing to match.
  scope :matching, ->(query) {
    term = "%#{sanitize_sql_like(query.to_s.strip)}%"
    joins(:member).where(
      "documents.label LIKE :t OR documents.kind LIKE :t OR documents.issuing_country LIKE :t OR members.name LIKE :t",
      t: term
    )
  }

  def context = applying_from.presence || Renewaru::Rule::Context::DOMESTIC

  # Nil when the dataset has no rule for this country and kind. That is a real
  # and permanent state — the dataset is deliberately incomplete — so every
  # caller has to cope with it rather than assume a rule exists.
  def rule = @rule ||= RuleCatalog.find(issuing_country, kind)

  def resolved
    return nil unless rule

    @resolved ||= rule.resolve(RuleCatalog.normalise_context(rule, context))
  end

  # Only meaningful for something with a deadline. A degree certificate has an
  # issuing country and a kind, and there is nothing to compute from them.
  def timeline = dated? ? resolved&.timeline : nil

  def title
    label.presence || rule&.title || kind.to_s.tr("_", " ").capitalize
  end

  def start_by
    return nil unless timeline

    expires_on - timeline.start_days_before_expiry
  end

  def days_until_start
    start_by && (start_by - Date.current).to_i
  end

  # Documents worth keeping that the renewal dataset says nothing about, because
  # they mostly do not expire. This list is open on purpose: the dataset's
  # document_kind enum is closed so the app never meets a kind it has no rule
  # UI for, but the *vault* has no such constraint — refusing to store a
  # transcript because nobody has written a renewal rule for transcripts would
  # be the tail wagging the dog.
  STORED_KINDS = {
    "Identity and family" => %w[
      birth_certificate marriage_certificate citizenship_certificate national_id
    ],
    "Education" => %w[degree_certificate academic_transcript school_certificate],
    "Property and money" => %w[property_deed land_certificate tax_document bank_document],
    "Work and health" => %w[employment_contract medical_record vaccination_record],
    "Other" => %w[other]
  }.freeze

  # Whether this document has a deadline at all. A degree certificate does not,
  # and that is not a missing field — it is the normal case for most of what a
  # household keeps.
  def dated? = expires_on.present?

  def days_until_expiry = dated? ? (expires_on - Date.current).to_i : nil

  def expired? = dated? && days_until_expiry.negative?
  def feasible? = timeline.nil? || timeline.feasible?

  # Mirrors RenewalCalculation#status so the dashboard and the public calculator
  # can never disagree about how much trouble somebody is in.
  #
  # `:stored` and `:unknown` are deliberately different answers. `:stored` means
  # this document does not expire and there is nothing to watch — a complete,
  # correct, finished state. `:unknown` means it *does* expire and we have no
  # rule for it, so we can warn about the expiry date but cannot say when to
  # start. Collapsing the two would tell somebody their birth certificate was
  # missing information it will never have.
  def status
    return :stored unless dated?
    return :unknown unless timeline
    return :expired if expired?
    return :impossible unless timeline.feasible?
    return :overdue if days_until_start.negative?
    return :now if days_until_start <= 30

    :ahead
  end

  # True when this document wants somebody's attention. Everything else is
  # simply filed, which is most of the vault and is not a problem to be solved.
  def needs_attention? = %i[expired overdue impossible now].include?(status)

  # Orders the attention list. Trouble first, then by how soon action is needed.
  # `stored` sorts last because it is never in this list at all.
  SEVERITY = { expired: 0, overdue: 1, impossible: 2, now: 3, ahead: 4, unknown: 5, stored: 6 }.freeze

  def severity = SEVERITY.fetch(status, 6)

  # Deliberately a sort key rather than <=> plus Comparable. Comparable defines
  # ==, which would replace ActiveRecord's identity comparison and blow up on
  # any comparison against nil or a non-Document — including the ones Rails
  # makes internally.
  # A stored document has neither date, so it sorts on the sentinel rather than
  # on nil — comparing nil against a Date raises, and a sort that blows up on
  # the most common kind of document in the vault is not one to leave to luck.
  UNDATED = Date.new(9999, 12, 31)

  def sort_key = [ severity, start_by || expires_on || UNDATED ]

  def schedule = ReminderSchedule.new(self)
  def chain = PrerequisiteChain.new(self)

  private

  def reset_reminders
    reminders.delete_all
  end
end
