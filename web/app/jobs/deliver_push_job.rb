# frozen_string_literal: true

# Pushes one reminder to every device a household has registered.
#
# Separate from DeliverRemindersJob on purpose. That job sweeps every document
# in the system and must run to completion every night; a push service being
# slow or unreachable is not a reason for the sweep to be still going at nine in
# the morning. This also means a push failure retries on its own schedule
# without re-sending the email alongside it.
class DeliverPushJob < ApplicationJob
  queue_as :default

  # A reminder already claimed and emailed. Retrying delivery to a dead endpoint
  # forever helps nobody.
  discard_on ActiveJob::DeserializationError

  def perform(document, kind, urgency)
    return unless PushSubscription.configured?

    subscriptions = PushSubscription.active.where(user: document.member.household.users)
    return if subscriptions.empty?

    title = ReminderNotification.title(document, urgency)
    body = ReminderNotification.body(document)
    path = Rails.application.routes.url_helpers.document_path(document)

    subscriptions.find_each do |subscription|
      subscription.deliver(title:, body:, path:)
    rescue StandardError => e
      # One unreachable push service must not stop the others, for the same
      # reason one malformed document must not stop the sweep.
      Rails.logger.error("DeliverPushJob: subscription #{subscription.id} failed: #{e.class}: #{e.message}")
      Rails.error.report(e, handled: true, context: { subscription_id: subscription.id, kind: kind })
    end
  end
end
