# frozen_string_literal: true

require "test_helper"

class ReminderScheduleTest < ActiveSupport::TestCase
  def document(**overrides)
    documents(:passport).tap { |doc| doc.assign_attributes(overrides) }
  end

  test "anchors every alert to the start date, not the expiry date" do
    doc = document(expires_on: Date.new(2028, 6, 30))
    schedule = ReminderSchedule.new(doc)

    start_now = schedule.entries.find { |e| e.kind == "start_now" }

    assert_equal doc.start_by, start_now.on
    # The point of the whole design: the first alert lands long before expiry.
    assert_operator schedule.entries.first.on, :<, doc.expires_on - 30
  end

  test "warns before the start date and chases after it" do
    schedule = ReminderSchedule.new(document(expires_on: Date.new(2028, 6, 30)))
    kinds = schedule.entries.map(&:kind)

    assert_equal %w[start_in_30 start_in_7 start_now overdue_14 overdue_45], kinds
    assert_equal schedule.entries.map(&:on).sort, schedule.entries.map(&:on)
  end

  test "falls back to expiry-anchored alerts when there is no rule" do
    doc = document(kind: "warranty", issuing_country: "DE", expires_on: Date.new(2028, 6, 30))
    schedule = ReminderSchedule.new(doc)

    assert_nil doc.timeline
    assert_not_predicate schedule, :anchored?
    assert_equal %w[expiry_90 expiry_30 expiry_7], schedule.entries.map(&:kind)
    assert_equal doc.expires_on - 90, schedule.entries.first.on
  end

  test "due includes stages whose moment has passed" do
    doc = document(expires_on: 40.days.from_now.to_date)
    schedule = ReminderSchedule.new(doc)

    assert_predicate schedule.due, :any?, "an already-late document should have due alerts"
  end

  test "due is empty when nothing has come round yet" do
    schedule = ReminderSchedule.new(document(expires_on: 10.years.from_now.to_date))

    assert_empty schedule.due
  end

  # Adding a long-overdue document must not fire five emails at once — that
  # trains the recipient to ignore the channel the product depends on.
  test "most_urgent_due picks the latest applicable stage only" do
    schedule = ReminderSchedule.new(document(expires_on: 20.days.from_now.to_date))

    assert_operator schedule.due.size, :>, 1
    assert_equal schedule.due.last.kind, schedule.most_urgent_due.kind
  end

  test "most_urgent_due skips stages already sent" do
    schedule = ReminderSchedule.new(document(expires_on: 20.days.from_now.to_date))
    all = schedule.due.map(&:kind)

    assert_nil schedule.most_urgent_due(excluding: all)
  end
end
