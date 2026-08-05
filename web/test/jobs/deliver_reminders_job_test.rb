# frozen_string_literal: true

require "test_helper"

class DeliverRemindersJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    # Isolate each case: the fixtures carry documents at various stages.
    Document.delete_all
    @member = members(:rajan)
  end

  def add_document(expires_in:, **overrides)
    @member.documents.create!(
      { kind: "passport", issuing_country: "NP", applying_from: "GB",
        expires_on: expires_in.from_now.to_date }.merge(overrides)
    )
  end

  test "sends nothing when no deadline is near" do
    add_document(expires_in: 10.years)

    assert_no_enqueued_emails { DeliverRemindersJob.perform_now }
  end

  test "sends when a stage comes due" do
    document = add_document(expires_in: 200.days)

    assert_enqueued_emails 1 do
      DeliverRemindersJob.perform_now
    end

    assert_equal 1, document.reminders.count
    assert_predicate document.reminders.first.sent_at, :present?
  end

  # The dedupe guarantee. A daily sweep must not re-send yesterday's alert.
  test "does not repeat a stage on later runs" do
    add_document(expires_in: 200.days)

    assert_enqueued_emails 1 do
      DeliverRemindersJob.perform_now
      DeliverRemindersJob.perform_now
      DeliverRemindersJob.perform_now
    end
  end

  test "advances to the next stage when its date arrives" do
    document = add_document(expires_in: 200.days)
    DeliverRemindersJob.perform_now
    first = document.reminders.sole.kind

    travel_to 40.days.from_now do
      assert_enqueued_emails 1 do
        DeliverRemindersJob.perform_now
      end
    end

    assert_equal 2, document.reminders.count
    assert_not_equal first, document.reminders.order(:id).last.kind
  end

  # Adding something already badly late should produce one clear message, not
  # a burst of five.
  test "sends a single message for a document added long overdue" do
    add_document(expires_in: 20.days)

    assert_enqueued_emails 1 do
      DeliverRemindersJob.perform_now
    end
  end

  test "emails every user in the household" do
    household = households(:one)
    household.users.create!(email_address: "partner@example.com", password: "correct horse")
    add_document(expires_in: 200.days)

    assert_enqueued_emails household.users.count do
      DeliverRemindersJob.perform_now
    end
  end

  test "does not email another household about this document" do
    add_document(expires_in: 200.days)

    perform_enqueued_jobs do
      DeliverRemindersJob.perform_now
    end

    recipients = ActionMailer::Base.deliveries.flat_map(&:to)

    assert_includes recipients, users(:one).email_address
    assert_not_includes recipients, users(:two).email_address
  end

  test "still reminds about a document with no renewal rule" do
    document = add_document(expires_in: 60.days, kind: "warranty", issuing_country: "DE", applying_from: nil)

    assert_nil document.timeline

    assert_enqueued_emails 1 do
      DeliverRemindersJob.perform_now
    end

    assert_match(/expiry/, document.reminders.sole.kind)
  end

  # Correcting a date has to reshape the whole cascade, or the user is stuck
  # with alerts computed from a typo.
  test "changing the expiry date resets the cascade" do
    document = add_document(expires_in: 200.days)
    DeliverRemindersJob.perform_now

    assert_equal 1, document.reminders.count

    document.update!(expires_on: 10.years.from_now.to_date)

    assert_equal 0, document.reminders.count
    assert_no_enqueued_emails { DeliverRemindersJob.perform_now }
  end

  # The sweep has to run to completion every night for everybody. One row that
  # blows up must not take the rest of the household's reminders with it.
  test "one broken document does not stop the sweep" do
    add_document(expires_in: 200.days)
    broken = add_document(expires_in: 200.days, kind: "police_clearance")

    build_schedule = ReminderSchedule.method(:new)
    ReminderSchedule.define_singleton_method(:new) do |document|
      raise "simulated failure" if document.id == broken.id

      build_schedule.call(document)
    end

    begin
      assert_enqueued_emails 1 do
        DeliverRemindersJob.perform_now
      end
    ensure
      ReminderSchedule.singleton_class.remove_method(:new)
    end
  end
end
