# frozen_string_literal: true

class PlaybooksController < ApplicationController
  # Public. These pages are the acquisition channel; a login wall in front of
  # them would make the entire content strategy pointless.
  allow_unauthenticated_access

  def index
    @rules = RuleCatalog.rules.sort_by { |rule| [ rule.country_code, rule.title ] }
    @playbook_count = RuleCatalog.playbooks.size
  end

  def show
    @resolved = RuleCatalog.resolve(params[:country_code], params[:document_kind], params[:origin])
    @rule = @resolved.rule
    @timeline = @resolved.timeline
    @other_contexts = RuleCatalog.origins_for(@rule) - [ @resolved.context ]
  rescue RuleCatalog::UnknownRule
    render "shared/not_found", status: :not_found
  end
end
