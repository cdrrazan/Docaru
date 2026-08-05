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
      redirect_to new_document_path(document: @result.to_document_attributes),
                  notice: repair_notice(@result)
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  # Said out loud rather than applied quietly. The check digits proved the
  # correction, but the person is holding the document and can confirm a date
  # faster than any checksum can be certain of one.
  def repair_notice(result)
    return nil unless result.repaired?

    "Read it. #{helpers.pluralize(result.repaired.size, "character")} looked like a letter where " \
      "only a digit is allowed (#{result.repaired.join(", ")}) and were corrected — the check " \
      "digits agree, but please confirm the expiry date against the document."
  end
end
