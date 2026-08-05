# frozen_string_literal: true

class PlaybooksController < ApplicationController
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
