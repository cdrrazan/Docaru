# frozen_string_literal: true

# How a reminder is worded, in one place.
#
# Email and push say the same thing because they are the same message arriving
# by two routes, and a household reading "start today" on a phone and "in a
# month" in an inbox would trust neither. Kept out of both the mailer and the
# job for the same reason Timeline keeps its phrasing out of the views.
#
# The wording carries the deadline rather than teasing it. A notification that
# says "you have an update" costs the reader a tap to learn something the
# notification could have told them, and this one is competing with everything
# else on a lock screen.
module ReminderNotification
  class << self
    def title(document, urgency)
      who = document.member.name
      what = document.title

      case urgency.to_s
      when "heads_up" then "In a month: start renewing #{who}'s #{what}"
      when "soon" then "Next week: start renewing #{who}'s #{what}"
      when "act" then "Start renewing #{who}'s #{what} today"
      when "overdue" then "Overdue: #{who}'s #{what} renewal should have started"
      when "critical" then "Urgent: #{who}'s #{what} expires #{document.expires_on.strftime("%-d %B")}"
      else "#{who}'s #{what}"
      end
    end

    # The one sentence underneath. Says why now rather than repeating the title.
    def body(document)
      timeline = document.timeline
      return "Expires #{document.expires_on.strftime("%-d %B %Y")}." unless timeline

      if document.expired?
        "Expired #{document.expires_on.strftime("%-d %B %Y")}."
      elsif !timeline.feasible?
        "The renewal window is shorter than the process takes. Plan for a gap."
      else
        "Processing takes up to #{timeline.processing_days} days, so this is the date to begin — " \
          "it expires #{document.expires_on.strftime("%-d %B %Y")}."
      end
    end
  end
end
