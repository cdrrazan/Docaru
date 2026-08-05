# frozen_string_literal: true

module DocumentsHelper
  STATUS_LABELS = {
    expired: "Expired",
    overdue: "Start overdue",
    impossible: "Window too short",
    now: "Start now",
    ahead: "On track",
    unknown: "No rule yet"
  }.freeze

  STATUS_CLASSES = {
    expired: "tag tag-warn",
    overdue: "tag tag-warn",
    impossible: "tag",
    now: "tag",
    ahead: "tag tag-ok",
    unknown: "tag tag-soft"
  }.freeze

  def status_tag(document)
    status = document.status
    tag.span(STATUS_LABELS.fetch(status), class: STATUS_CLASSES.fetch(status))
  end

  # One sentence a person can act on. Says the uncomfortable thing plainly —
  # a reassuring date that has already passed is worse than no date.
  def document_verdict(document)
    case document.status
    when :expired
      "Expired #{pluralize(document.days_until_expiry.abs, "day")} ago, on #{document.expires_on.strftime("%-d %B %Y")}."
    when :overdue
      "You should have started #{pluralize(document.days_until_start.abs, "day")} ago. " \
        "It expires #{document.expires_on.strftime("%-d %B %Y")} — start now."
    when :impossible
      document.timeline.verdict
    when :now
      document.days_until_start.zero? ? "Start today." : "Start within #{pluralize(document.days_until_start, "day")}."
    when :ahead
      "Start on #{document.start_by.strftime("%-d %B %Y")}, ahead of expiry on #{document.expires_on.strftime("%-d %B %Y")}."
    else
      "Expires #{document.expires_on.strftime("%-d %B %Y")}. " \
        "No renewal rule for this document yet, so we cannot work out a start date — only the expiry."
    end
  end
end
