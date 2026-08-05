# frozen_string_literal: true

require "test_helper"

class AttachmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @document = documents(:passport)
  end

  # Stands in for what the browser sends: bytes the server cannot interpret.
  def ciphertext_file(bytes = "\x00\x01\x02not-readable-without-the-key")
    Rack::Test::UploadedFile.new(StringIO.new(bytes), "application/octet-stream", true, original_filename: "page.bin")
  end

  def valid_params(**overrides)
    { attachment: {
      iv: Base64.strict_encode64(SecureRandom.bytes(12)),
      content_type: "image/webp",
      byte_size: 4096,
      page_no: 1,
      ciphertext: ciphertext_file
    }.merge(overrides) }
  end

  test "requires authentication" do
    sign_out
    post document_attachments_path(@document), params: valid_params

    assert_redirected_to new_session_path
  end

  test "accepts an encrypted page" do
    assert_difference "Attachment.count", 1 do
      post document_attachments_path(@document), params: valid_params
    end

    assert_response :created
    assert_predicate Attachment.last.ciphertext, :attached?
  end

  # The whole promise. Anything the server stores about the file must be
  # useless for working out what the document says.
  test "stores no plaintext and no filename" do
    post document_attachments_path(@document), params: valid_params
    attachment = Attachment.last

    assert_not attachment.respond_to?(:filename)
    assert_not attachment.attributes.key?("plaintext")
    # The blob's own filename is fixed by the client, never the user's.
    assert_equal "page.bin", attachment.ciphertext.filename.to_s
  end

  test "returns ciphertext as an opaque download, never inline" do
    post document_attachments_path(@document), params: valid_params
    attachment = Attachment.last

    get document_attachment_path(@document, attachment)

    assert_response :success
    assert_equal "application/octet-stream", response.media_type
    assert_match(/attachment/, response.headers["Content-Disposition"])
  end

  test "rejects a nonce that is not a nonce" do
    assert_no_difference "Attachment.count" do
      post document_attachments_path(@document), params: valid_params(iv: "nope")
    end

    assert_response :unprocessable_entity
  end

  test "rejects an unsupported content type" do
    assert_no_difference "Attachment.count" do
      post document_attachments_path(@document), params: valid_params(content_type: "text/html")
    end

    assert_response :unprocessable_entity
  end

  test "rejects an implausible size" do
    assert_no_difference "Attachment.count" do
      post document_attachments_path(@document), params: valid_params(byte_size: 50.megabytes)
    end

    assert_response :unprocessable_entity
  end

  test "cannot attach to another household's document" do
    assert_no_difference "Attachment.count" do
      post document_attachments_path(documents(:stranger_passport)), params: valid_params
    end

    assert_response :not_found
  end

  test "cannot read another household's attachment" do
    stranger = documents(:stranger_passport)
    attachment = stranger.attachments.create!(iv: Base64.strict_encode64(SecureRandom.bytes(12)),
                                              content_type: "image/webp", byte_size: 100, page_no: 1)

    get document_attachment_path(stranger, attachment)

    assert_response :not_found
  end

  test "removing a document removes its encrypted pages" do
    post document_attachments_path(@document), params: valid_params

    assert_difference "Attachment.count", -1 do
      @document.destroy
    end
  end
end
