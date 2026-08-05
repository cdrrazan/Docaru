# frozen_string_literal: true

class ReminderMailer < ApplicationMailer
  def deadline
    @user = params[:user]
    @document = params[:document]
    @kind = params[:kind]
    @urgency = params[:urgency].to_s
    @resolved = @document.resolved
    @timeline = @document.timeline

    mail to: @user.email_address, subject: subject_line
  end

  private

  # The subject line is most of the product. It has to say what to do, to whom,
  # and by when — because for a great many recipients the subject is the only
  # part that gets read.
  def subject_line
    who = @document.member.name
    what = @document.title

    case @urgency
    when "heads_up"
      "In a month: start renewing #{who}'s #{what}"
    when "soon"
      "Next week: start renewing #{who}'s #{what}"
    when "act"
      "Start renewing #{who}'s #{what} today"
    when "overdue"
      "Overdue: #{who}'s #{what} renewal should have started"
    when "critical"
      "Urgent: #{who}'s #{what} expires #{@document.expires_on.strftime("%-d %B")}"
    else
      "#{who}'s #{what}"
    end
  end
end
