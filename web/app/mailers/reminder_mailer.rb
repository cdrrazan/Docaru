# frozen_string_literal: true

class ReminderMailer < ApplicationMailer
  def deadline
    @user = params[:user]
    @document = params[:document]
    @kind = params[:kind]
    @urgency = params[:urgency].to_s
    @resolved = @document.resolved
    @timeline = @document.timeline
    @chain = @document.chain

    mail to: @user.email_address, subject: subject_line
  end

  private

  # The subject line is most of the product. It has to say what to do, to whom,
  # and by when — because for a great many recipients the subject is the only
  # part that gets read.
  #
  # Shared with the push notification, which is the same message arriving by
  # another route. A household reading "start today" on a phone and "in a month"
  # in an inbox would trust neither.
  def subject_line = ReminderNotification.title(@document, @urgency)
end
