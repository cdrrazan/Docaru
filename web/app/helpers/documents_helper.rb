# frozen_string_literal: true

module DocumentsHelper
  # "Stored" is a finished state, not a deficiency. A birth certificate is not
  # missing an expiry date; it does not have one, and the label has to say that
  # without implying somebody forgot to fill a field in.
  STATUS_LABELS = {
    expired: "Expired",
    overdue: "Start overdue",
    impossible: "Window too short",
    now: "Start now",
    ahead: "On track",
    unknown: "No rule yet",
    stored: "Stored"
  }.freeze

  STATUS_CLASSES = {
    expired: "tag tag-warn",
    overdue: "tag tag-warn",
    impossible: "tag",
    now: "tag",
    ahead: "tag tag-ok",
    unknown: "tag tag-soft",
    stored: "tag tag-soft"
  }.freeze

  REMINDER_LABELS = {
    "start_in_30" => "A month before you need to start",
    "start_in_7" => "A week before you need to start",
    "start_now" => "The day to start",
    "overdue_14" => "Two weeks late",
    "overdue_45" => "Six weeks late",
    "expiry_90" => "90 days before it expires",
    "expiry_30" => "30 days before it expires",
    "expiry_7" => "7 days before it expires"
  }.freeze

  def status_tag(document)
    status = document.status
    tag.span(STATUS_LABELS.fetch(status), class: STATUS_CLASSES.fetch(status))
  end

  def reminder_label(entry) = REMINDER_LABELS.fetch(entry.kind, entry.kind.humanize)

  # Grouped so the difference is visible in the menu rather than discovered
  # afterwards: the first group gets a start-by date because a public rule
  # exists for it, and everything else is stored and reachable, which is the
  # larger half of the point.
  def document_kind_options(selected)
    renewable = RuleCatalog.rules.sort_by(&:title).map { |rule| [ rule.title, rule.document_kind ] }

    grouped = { "Renewal guidance available" => renewable }
    Document::STORED_KINDS.each do |group, kinds|
      grouped[group] = kinds.map { |kind| [ kind.tr("_", " ").capitalize, kind ] }
    end

    grouped_options_for_select(grouped, selected)
  end

  def status_headline(document)
    case document.status
    when :stored then "Stored"
    when :expired then "Expired"
    when :overdue then "You should have started already"
    when :impossible then "Cannot be finished before it expires"
    when :now then "Start now"
    when :ahead then "Start on #{document.start_by.strftime("%-d %B %Y")}"
    else "Expires #{document.expires_on.strftime("%-d %B %Y")}"
    end
  end

  # One sentence a person can act on. Says the uncomfortable thing plainly —
  # a reassuring date that has already passed is worse than no date.
  def document_verdict(document)
    case document.status
    when :stored
      # Said as a completed fact rather than an absence. Somebody who stored a
      # degree certificate did not fail to enter an expiry date.
      "Kept here so you can reach it from anywhere. This one does not expire, so there is " \
        "nothing to renew and nothing to remind you about."
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
