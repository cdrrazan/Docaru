# frozen_string_literal: true

# The cascade of alerts for one document.
#
# Everything here is anchored to **start by**, not to expiry. That is the whole
# argument of the product: a reminder that fires against the expiry date is
# correct and useless, because by the time it arrives the fourteen weeks of
# processing you needed are no longer available. Anchoring to the start date
# means the first alert lands while there is still time to act on it.
#
# Nothing is persisted from here. The schedule is derived on every sweep, so
# fixing a wrong expiry date reshapes all future alerts without a migration or
# a backfill.
class ReminderSchedule
  Entry = Struct.new(:kind, :on, :urgency, keyword_init: true)

  # Offsets in days from the start-by date. Negative means before it.
  # The tail past the start date exists because the failure mode is not
  # forgetting — it is intending to deal with it and not getting round to it.
  ANCHORED = [
    { kind: "start_in_30", offset: -30, urgency: :heads_up },
    { kind: "start_in_7",  offset: -7,  urgency: :soon },
    { kind: "start_now",   offset: 0,   urgency: :act },
    { kind: "overdue_14",  offset: 14,  urgency: :overdue },
    { kind: "overdue_45",  offset: 45,  urgency: :critical }
  ].freeze

  # Used when the dataset has no rule for the document, so there is no start-by
  # date to anchor to. Worth far less, and honest about it — but a document with
  # no rule still has an expiry date, and silence would be worse.
  FALLBACK = [
    { kind: "expiry_90", offset: -90, urgency: :heads_up },
    { kind: "expiry_30", offset: -30, urgency: :soon },
    { kind: "expiry_7",  offset: -7,  urgency: :overdue }
  ].freeze

  attr_reader :document

  def initialize(document)
    @document = document
  end

  def anchored? = document.start_by.present?

  def entries
    # A document with no expiry date has nothing to remind anybody about, and
    # that is the normal case for most of a vault — a degree certificate is not
    # a deadline that has gone missing. Silence here is correct; inventing a
    # date to alert on would be the bug.
    return [] unless document.dated?

    anchor = document.start_by
    return fallback_entries unless anchor

    ANCHORED.map do |stage|
      Entry.new(kind: stage[:kind], on: anchor + stage[:offset], urgency: stage[:urgency])
    end
  end

  # Everything whose moment has arrived. Past-dated entries are included on
  # purpose: somebody who adds a document that is already overdue should hear
  # about it immediately, not wait for the next stage to come round.
  def due(as_of: Date.current)
    entries.select { |entry| entry.on <= as_of }
  end

  # The single most urgent thing outstanding. Sending five emails at once
  # because a document was added late would train the recipient to ignore all
  # of them, so a sweep sends one message per document at most.
  def most_urgent_due(as_of: Date.current, excluding: [])
    due(as_of: as_of).reject { |entry| excluding.include?(entry.kind) }.max_by { |entry| entries.index(entry) }
  end

  private

  def fallback_entries
    FALLBACK.map do |stage|
      Entry.new(kind: stage[:kind], on: document.expires_on + stage[:offset], urgency: stage[:urgency])
    end
  end
end
