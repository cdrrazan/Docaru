# frozen_string_literal: true

require "date"

module Renewaru
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

    private

    def to_date(value)
      value.is_a?(Date) ? value : Date.parse(value.to_s)
    end
  end
end
