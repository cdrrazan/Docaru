# frozen_string_literal: true

# Receives and returns already-encrypted bytes.
#
# There is deliberately no code here that decrypts, inspects, resizes or
# thumbnails an attachment. The server treats the payload as opaque, because the
# moment it does anything useful with the plaintext it has to be able to read
# the plaintext — and then the promise in spec §7 is gone.
class AttachmentsController < ApplicationController
  before_action :set_document

  def create
    @attachment = @document.attachments.new(attachment_params)

    # Checked here rather than in a validation because the number that matters
    # is the household's total, and the attachment does not know its household
    # without walking two associations to find out. Checked at all because the
    # byte count arrives from the browser, and a browser is free to lie about
    # it — the stored blob is what costs, so the stored blob is what is counted.
    unless household.can_store?(@attachment.byte_size)
      return render json: { errors: [ storage_full_message ] }, status: :content_too_large
    end

    if @attachment.save
      render json: { id: @attachment.id, page_no: @attachment.page_no }, status: :created
    else
      render json: { errors: @attachment.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # Serves the ciphertext for the browser to decrypt. Never inline: the bytes
  # are not a renderable image to anyone without the key, and Content-Disposition
  # attachment keeps a browser from trying to interpret them.
  def show
    attachment = @document.attachments.find(params[:id])

    return head :not_found unless attachment.ciphertext.attached?

    send_data attachment.ciphertext.download,
              type: "application/octet-stream",
              disposition: "attachment",
              filename: "page-#{attachment.page_no}.bin"
  end

  def destroy
    @document.attachments.find(params[:id]).destroy
    redirect_to document_path(@document), notice: "Page removed."
  end

  private

  # Scoped through the household, so another household's document id is a 404.
  def set_document
    @document = household.documents.find(params[:document_id])
  end

  def attachment_params
    params.expect(attachment: [ :iv, :content_type, :byte_size, :page_no, :ciphertext ])
  end

  def storage_full_message
    helpers.number_to_human_size(household.storage_limit).then do |limit|
      "That would take you past your #{limit} of storage. " \
        "Nothing already stored is affected — upgrade for more room, or remove a page you no longer need."
    end
  end
end
