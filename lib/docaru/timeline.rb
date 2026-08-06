# frozen_string_literal: true

require "date"

module Docaru
  # Turns a resolved rule into the only number the product actually sells:
  # the date you have to start.
  #
  #   required_lead = processing.worst_case
  #                 + slowest mandatory prerequisite
  #                 + buffer
  #
  # Worst case rather than typical, deliberately. A reminder derived from the
  # median is correct for the median applicant and useless for the tail, and the
  # tail is where a missed deadline costs someone their legal status.
  class Timeline
    attr_reader :resolved

    def initialize(resolved)
      @resolved = resolved
    end

    def processing_days = resolved.processing&.fetch("worst_case", 0).to_i
    def typical_days = resolved.processing&.fetch("typical", 0).to_i
    def prerequisite_days = resolved.prerequisite_lead_days
    def buffer_days = resolved.buffer_days

    def required_lead_days
      processing_days + prerequisite_days + buffer_days
    end

    def window_opens_days_before = resolved.window_opens_days_before.to_i

    # You cannot start before the law lets you, however much lead time you need.
    def start_days_before_expiry
      [required_lead_days, window_opens_days_before].min
    end

    # True where there exists a legal start date that still finishes before expiry.
    def feasible?
      required_lead_days <= window_opens_days_before
    end

    # How many days late you land if you start on the first legal day.
    def shortfall_days
      feasible? ? 0 : required_lead_days - window_opens_days_before
    end

    # An infeasible process is survivable where the authority allows late renewal.
    def covered_by_grace?
      !feasible? && shortfall_days <= resolved.grace_days
    end

    def start_by(expires_on)
      to_date(expires_on) - start_days_before_expiry
    end

    def window_opens_on(expires_on)
      to_date(expires_on) - window_opens_days_before
    end

    def projected_completion(expires_on)
      to_date(expires_on) - window_opens_days_before + required_lead_days
    end

    # One sentence a person can act on, which is what every layer above this
    # eventually has to render.
    def verdict
      if feasible?
        "Start #{start_days_before_expiry} days before expiry — about #{months(start_days_before_expiry)}."
      elsif covered_by_grace?
        "Cannot be completed before expiry: the earliest legal start still lands about " \
          "#{shortfall_days} days late. Late renewal is permitted here, so plan for the gap " \
          "and the penalty rather than for an on-time finish."
      else
        "Cannot be completed before expiry from here. The earliest legal start still finishes " \
          "about #{shortfall_days} days late, and there is no grace period. Expect a period " \
          "without a valid document, and plan around that rather than around the deadline."
      end
    end

    def months(days)
      m = (days / 30.0).round
      m <= 1 ? "a month" : "#{m} months"
    end

    # ---- window phrasing -----------------------------------------------------
    #
    # Kept here rather than in a view so the web app and the static generator
    # cannot describe the same rule differently.

    def window_opens_phrase
      opens = window_opens_days_before
      return "You may apply at any time." if opens >= 3650

      "The earliest you may apply is #{opens} days before expiry."
    end

    def window_closes_phrase
      closes = resolved.window_closes_days_before.to_i
      grace = resolved.grace_days

      if closes.positive?
        "Applications close #{closes} days before expiry."
      elsif closes.zero?
        "Applications close on the expiry date itself; there is no grace period afterwards."
      elsif grace >= 3650
        # The large negative value is a sentinel for "there is no deadline on
        # renewing an expired one". Rendering it as a day count invites the
        # reader to plan against a number that means nothing.
        "An expired document can still be renewed rather than applied for from scratch, " \
          "so there is no cut-off — but the consequences of the gap still apply."
      elsif grace >= 365
        years = (grace / 365.0).round
        "Late applications are still accepted for up to #{years} year#{"s" unless years == 1} " \
          "after expiry, though penalties may apply."
      else
        "Late applications are still accepted for #{grace} days after expiry, though penalties may apply."
      end
    end

    private

    def to_date(value)
      value.is_a?(Date) ? value : Date.parse(value.to_s)
    end
  end
end
