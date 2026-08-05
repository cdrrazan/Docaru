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
end
