# frozen_string_literal: true

# Reading the machine-readable zone to prefill a document, instead of asking
# somebody to type it. Cold start is the biggest risk the product has, and
# data entry is what kills it.
class ScansController < ApplicationController
  def new
    @result = nil
  end

  def create
    @result = MachineReadableZone.parse(params[:mrz])

    if @result.valid?
      # Straight to the document form with the fields filled in. The MRZ is
      # never stored: it carries a name, a sex and a date of birth that are of
      # no use in computing a renewal date, so they are read and discarded.
      redirect_to new_document_path(document: @result.to_document_attributes)
    else
      render :new, status: :unprocessable_entity
    end
  end
end
