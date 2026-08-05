class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "reminders@example.com")
  layout "mailer"

  # Reminder emails render the same verdicts and links the dashboard does, and
  # they must not drift from it — the email is where most people will read this.
  helper :application, :documents, :playbooks
end
