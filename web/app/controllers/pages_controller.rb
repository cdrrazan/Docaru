# frozen_string_literal: true

class PagesController < ApplicationController
  allow_unauthenticated_access

  def home
    @rules = RuleCatalog.rules.sort_by(&:title)
    @playbook_count = RuleCatalog.playbooks.size
    @country_count = RuleCatalog.countries.size
  end
end
