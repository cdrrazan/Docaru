# frozen_string_literal: true

class CalculationsController < ApplicationController
  # GET rather than POST, and the parameters stay in the URL, so a result can be
  # bookmarked, shared into a family chat, or linked from a forum answer. Those
  # links are also the distribution channel, which a POST would throw away.
  def show
    @calculation = RenewalCalculation.new(calculation_params)
    @submitted = calculation_params.values.any?(&:present?)
    @calculation.validate if @submitted
    @documents = RenewalCalculation.document_options
    @origins = RenewalCalculation.origin_options(@calculation.rule)
  end

  private

  # The document select carries "NP:passport" as one value so the two fields
  # cannot be combined into a pair that has no rule.
  def calculation_params
    country, kind = params[:document].to_s.split(":", 2)

    {
      country_code: country,
      document_kind: kind,
      applying_from: params[:from].presence || RenewalCalculation::DOMESTIC,
      expires_on: params[:expires_on].presence
    }
  end
end
