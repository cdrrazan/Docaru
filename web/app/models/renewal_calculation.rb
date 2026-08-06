# frozen_string_literal: true

# The anonymous calculator: a document, a place, an expiry date, and the one
# answer that matters — the date you have to start.
#
# Deliberately not an ActiveRecord model. Nothing is stored. Somebody checking
# when to renew their visa should be able to get an answer without handing over
# an account, and the honest way to promise that is to have nowhere to put it.
class RenewalCalculation
  include ActiveModel::Model
  include ActiveModel::Attributes

  DOMESTIC = Docaru::Rule::Context::DOMESTIC

  attribute :country_code, :string
  attribute :document_kind, :string
  attribute :applying_from, :string, default: DOMESTIC
  attribute :expires_on, :date

  validates :country_code, presence: { message: "Choose the country that issued the document" }
  validates :document_kind, presence: { message: "Choose a document" }
  validates :expires_on, presence: { message: "Enter the expiry date shown on the document" }

  validate :rule_must_exist
  validate :expiry_must_be_plausible

  def rule
    return nil if country_code.blank? || document_kind.blank?

    @rule ||= RuleCatalog.find(country_code, document_kind)
  end

  def resolved
    @resolved ||= rule&.resolve(RuleCatalog.normalise_context(rule, applying_from))
  end

  def timeline = resolved&.timeline

  # The headline date. Capped by the renewal window: there is no point telling
  # somebody to start eight months out if the authority will not accept an
  # application until three.
  def start_by
    return nil unless ready?

    expires_on - timeline.start_days_before_expiry
  end

  def window_opens_on
    return nil unless ready?

    expires_on - timeline.window_opens_days_before
  end

  # Where starting on the first legal day actually lands you. Only interesting
  # when that is after the expiry date.
  def projected_completion
    return nil unless ready?

    timeline.projected_completion(expires_on)
  end

  def days_until_start
    return nil unless ready?

    (start_by - Date.current).to_i
  end

  def days_until_expiry
    return nil unless expires_on

    (expires_on - Date.current).to_i
  end

  def ready? = valid? && resolved.present?

  # Drives both the wording and the colour of the answer. Ordered by severity:
  # an already-expired document outranks an impossible window, because the
  # holder's immediate problem is different.
  def status
    return :unknown unless ready?
    return :expired if days_until_expiry.negative?
    return :impossible unless timeline.feasible?
    return :overdue if days_until_start.negative?
    return :now if days_until_start <= 30

    :ahead
  end

  def headline
    case status
    when :expired
      "This expired #{pluralize_days(days_until_expiry.abs)} ago"
    when :impossible
      "You cannot finish this before it expires"
    when :overdue
      "You should have started #{pluralize_days(days_until_start.abs)} ago"
    when :now
      days_until_start.zero? ? "Start today" : "Start within #{pluralize_days(days_until_start)}"
    when :ahead
      "Start on #{start_by.strftime("%-d %B %Y")}"
    else
      "Not enough information"
    end
  end

  def explanation
    case status
    when :expired
      "It expired on #{expires_on.strftime("%-d %B %Y")}. #{renewal_or_fresh_application}"
    when :impossible
      timeline.verdict
    when :overdue
      "Working back from #{expires_on.strftime("%-d %B %Y")}, the process needs " \
        "#{timeline.required_lead_days} days and you have #{days_until_expiry}. " \
        "Start immediately and expect it to be tight."
    when :now, :ahead
      "It expires on #{expires_on.strftime("%-d %B %Y")}. The process needs " \
        "#{timeline.required_lead_days} days end to end, so the last safe moment to begin is " \
        "#{start_by.strftime("%-d %B %Y")}."
    end
  end

  # The forms only offer what the dataset can actually answer for.
  def self.document_options
    RuleCatalog.rules
               .sort_by { |rule| [ rule.country_code, rule.title ] }
               .map { |rule| [ rule.title, "#{rule.country_code}:#{rule.document_kind}" ] }
  end

  def self.origin_options(rule)
    return [] unless rule

    RuleCatalog.origins_for(rule).map do |context|
      label = context == DOMESTIC ? "In #{Docaru::Countries.title(rule.country_code)}" : "From #{Docaru::Countries.title(context)}"
      [ label, context ]
    end
  end

  private

  def renewal_or_fresh_application
    if resolved.grace_days.positive?
      "Late renewal is still accepted here, so start now — the sooner you do, the smaller the penalty."
    else
      "There is no grace period, so this is likely to be a fresh application rather than a renewal."
    end
  end

  def pluralize_days(count)
    "#{count} day#{"s" unless count == 1}"
  end

  def rule_must_exist
    return if country_code.blank? || document_kind.blank?
    return if rule

    errors.add(:document_kind, "There is no renewal rule for that document yet")
  end

  # Guards against a mistyped year producing a confidently absurd answer.
  def expiry_must_be_plausible
    return if expires_on.blank?

    if expires_on > Date.current.next_year(50)
      errors.add(:expires_on, "That is more than 50 years away — check the year")
    elsif expires_on < Date.current.prev_year(50)
      errors.add(:expires_on, "That is more than 50 years ago — check the year")
    end
  end
end
