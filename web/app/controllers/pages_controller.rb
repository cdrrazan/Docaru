# frozen_string_literal: true

class PagesController < ApplicationController
  allow_unauthenticated_access

  def home
    @rules = RuleCatalog.rules.sort_by(&:title)
    @playbook_count = RuleCatalog.playbooks.size
    @country_count = RuleCatalog.countries.size
  end

  # Generated from the dataset rather than maintained by hand, so adding a rule
  # file or an origin override publishes its pages without anybody remembering
  # to list them. Only the public plane appears here — everything behind
  # authentication is nobody's business to crawl.
  def sitemap
    @playbooks = RuleCatalog.playbooks
    @updated_on = RuleCatalog.rules.filter_map { |rule| rule.data["verified_on"] }.max

    expires_in 1.hour, public: true
    render formats: :xml
  end
end
