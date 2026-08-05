# frozen_string_literal: true

module PlaybooksHelper
  DOMESTIC = Renewaru::Rule::Context::DOMESTIC

  def country_name(code) = Renewaru::Countries.name(code)
  def country_title(code) = Renewaru::Countries.title(code)

  def playbook_path_for(rule, context)
    kind = rule.document_kind.tr("_", "-")
    country = rule.country_code.downcase

    if context.to_s == DOMESTIC
      playbook_path(country_code: country, document_kind: kind)
    else
      origin_playbook_path(country_code: country, document_kind: kind, origin: context.downcase)
    end
  end

  # Absolute form, for emails. A relative path in an email goes nowhere.
  def playbook_url_for(document_or_rule, context = nil)
    rule, ctx = if document_or_rule.is_a?(Document)
      [ document_or_rule.rule, document_or_rule.resolved&.context ]
    else
      [ document_or_rule, context ]
    end
    return dashboard_url unless rule

    kind = rule.document_kind.tr("_", "-")
    country = rule.country_code.downcase

    if ctx.to_s == DOMESTIC || ctx.blank?
      playbook_url(country_code: country, document_kind: kind)
    else
      origin_playbook_url(country_code: country, document_kind: kind, origin: ctx.downcase)
    end
  end

  # "in Nepal" / "from the United Kingdom" — the phrasing that reads naturally
  # in a heading and matches how the question gets asked.
  def context_phrase(rule, context)
    if context.to_s == DOMESTIC
      "in #{country_name(rule.country_code)}"
    else
      "from #{country_name(context)}"
    end
  end

  def context_label(rule, context)
    if context.to_s == DOMESTIC
      "In #{country_title(rule.country_code)}"
    else
      "From #{country_title(context)}"
    end
  end

  # Days are the unit the data is in, but nobody plans in days. Months read
  # better above a couple of months, and the exact figure stays alongside.
  def humanised_days(days)
    days = days.to_i
    return "#{days} days" if days < 60

    months = (days / 30.0).round
    "#{days} days (about #{pluralize(months, "month")})"
  end

  def money(cost)
    return nil unless cost

    amount = cost["amount"].to_f
    return nil unless amount.positive?

    "#{cost["currency"]} #{number_with_delimiter(amount.round)}"
  end

  def status_badge(resolved)
    if resolved.draft?
      tag.span("unverified", class: "tag tag-soft", title: "No human has checked this against the authority yet")
    else
      tag.span("verified #{resolved.verified_on}", class: "tag tag-ok")
    end
  end
end
