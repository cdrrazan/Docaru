# frozen_string_literal: true

require "test_helper"

class ReminderMailerTest < ActionMailer::TestCase
  def mail_for(document, kind: "start_now", urgency: "act")
    ReminderMailer.with(user: users(:one), document: document, kind: kind, urgency: urgency).deadline
  end

  test "renders both parts without raising" do
    mail = mail_for(documents(:passport))

    assert_equal [ users(:one).email_address ], mail.to
    assert_predicate mail.html_part.body.to_s, :present?
    assert_predicate mail.text_part.body.to_s, :present?
  end

  # The subject is most of the product: for many recipients it is the only part
  # that gets read, so it has to carry who, what and how urgent.
  test "the subject says what to do and for whom" do
    document = documents(:passport)

    assert_match(/Start renewing #{document.member.name}'s .*today/,
                 mail_for(document, urgency: "act").subject)
    assert_match(/^Overdue:/, mail_for(document, kind: "overdue_14", urgency: "overdue").subject)
    assert_match(/^Urgent:/, mail_for(document, kind: "overdue_45", urgency: "critical").subject)
  end

  test "leads with the start date, not the expiry date" do
    document = documents(:passport)
    body = mail_for(document).text_part.body.to_s

    assert_match document.start_by.strftime("%-d %B %Y"), body
    assert_match(/Start by/, body)
  end

  test "names the prerequisite that has to be ordered first" do
    body = mail_for(documents(:passport)).text_part.body.to_s

    assert_match(/FIRST THING TO DO/, body)
    assert_match(/citizenship certificate/i, body)
  end

  test "warns when the process cannot fit the window" do
    document = members(:rajan).documents.create!(
      kind: "drivers_licence", issuing_country: "NP", applying_from: "GB",
      expires_on: 1.year.from_now.to_date
    )

    assert_match(/cannot be completed before it expires/, mail_for(document).text_part.body.to_s)
  end

  test "says so when the underlying rule is unverified" do
    assert_match(/unverified/, mail_for(documents(:passport)).text_part.body.to_s)
  end

  test "falls back to an expiry reminder when there is no rule" do
    document = members(:rajan).documents.create!(
      kind: "warranty", issuing_country: "DE", expires_on: 30.days.from_now.to_date
    )
    body = mail_for(document, kind: "expiry_30", urgency: "soon").text_part.body.to_s

    assert_match(/no renewal rule for this document yet/, body)
  end

  test "links are absolute so they work from an inbox" do
    body = mail_for(documents(:passport)).text_part.body.to_s

    assert_match(%r{https?://[^/]+/playbooks/np/passport}, body)
  end
end
