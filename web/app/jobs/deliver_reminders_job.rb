# frozen_string_literal: true

# The nightly sweep. This job is the product: notifications are what retention
# depends on, because nobody opens a document vault for months at a time.
#
# It recomputes every schedule from the current rules rather than reading a
# queue, so a corrected expiry date or an updated renewal rule takes effect on
# the next run with no backfill.
class DeliverRemindersJob < ApplicationJob
  queue_as :default

  def perform(as_of: Date.current)
    Document.includes(member: { household: :users }).find_each do |document|
      deliver_for(document, as_of: as_of)
    rescue StandardError => e
      # One malformed document must not stop the sweep. The whole point of this
      # job is that it runs to completion every night for everybody.
      Rails.logger.error("DeliverRemindersJob: document #{document.id} failed: #{e.class}: #{e.message}")
      Rails.error.report(e, handled: true, context: { document_id: document.id })
    end
  end

  private

  def deliver_for(document, as_of:)
    already_sent = document.reminders.pluck(:kind)
    entry = document.schedule.most_urgent_due(as_of: as_of, excluding: already_sent)
    return unless entry

    recipients = document.member.household.users
    return if recipients.empty?

    # Claim the stage before sending. If delivery raises, the claim is rolled
    # back and tomorrow's sweep tries again; if it succeeds, the unique index
    # guarantees nobody gets it twice.
    Reminder.transaction do
      reminder = document.reminders.create!(kind: entry.kind, scheduled_for: entry.on)

      recipients.each do |user|
        # Primitives only: ActiveJob has to serialise these into the queue, and
        # a Struct is not something it can round-trip.
        ReminderMailer.with(
          user: user,
          document: document,
          kind: entry.kind,
          urgency: entry.urgency.to_s
        ).deadline.deliver_later
      end

      reminder.update!(sent_at: Time.current)
    end
  rescue ActiveRecord::RecordNotUnique
    # Another sweep got there first. Nothing to do.
    nil
  end
end
