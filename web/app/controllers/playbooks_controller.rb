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
    @rule = RuleCatalog.find!(params[:country_code], params[:document_kind])

    return if redirect_self_origin
    return head_unknown_origin if unknown_origin?

    @resolved = @rule.resolve(RuleCatalog.normalise_context(@rule, params[:origin]))
    @timeline = @resolved.timeline
    @other_contexts = RuleCatalog.origins_for(@rule) - [ @resolved.context ]
    @indexable = indexable_origin?
  rescue RuleCatalog::UnknownRule
    render "shared/not_found", status: :not_found
  end

  private

  def origin = params[:origin].presence&.upcase

  # Applying from the issuing country *is* the domestic case, and it already has
  # a URL. Left alone it renders "renewal from Nepal" against the abroad
  # processing times — a wrong answer, not merely a second address for a right
  # one — so this is a redirect rather than a canonical tag.
  def redirect_self_origin
    return false unless origin == @rule.country_code

    redirect_to playbook_path(country_code: @rule.country_code.downcase,
                              document_kind: @rule.document_kind.tr("_", "-")),
                status: :moved_permanently
    true
  end

  # The route matches any two letters, and RuleCatalog falls back to the
  # domestic view for anything it cannot place — correct for a stored document
  # with a junk origin, wrong for a URL, where it silently served the domestic
  # page at 676 addresses per document and asked crawlers to sort out which of
  # them was the real one.
  def unknown_origin? = origin.present? && !Docaru::Countries::NAMES.key?(origin)

  # Whether this page is worth putting in an index, which is not the same
  # question as whether it is worth serving.
  #
  # An origin the dataset has an override for is a distinct answer: different
  # processing times, different fees, different mission. An origin without one
  # renders the generic abroad timings, so every such page carries the same
  # substance as every other — and there are as many of them as there are
  # countries. Serving them is right, because somebody who typed one wants that
  # answer and the timings are honest. Indexing them would file 200-odd
  # near-identical pages per rule against the one that should be ranking.
  #
  # This is the same trade the calculator already makes for answered results,
  # for the same reason.
  def indexable_origin? = @resolved.domestic? || @rule.origins.include?(@resolved.context)

  def head_unknown_origin
    render "shared/not_found", status: :not_found
  end
end
