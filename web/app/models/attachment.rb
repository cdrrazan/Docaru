# frozen_string_literal: true

# An encrypted page of a document.
#
# The bytes arrive already encrypted. The server has no key, no way to obtain
# one, and no code path that attempts decryption — that is the point of the
# split in spec §7: it can compute reminders and render a dashboard from the
# metadata, but it has never seen a passport scan and could not produce one if
# compelled to.
#
# What is deliberately *not* stored: the filename, the plaintext size, and any
# thumbnail. Each of those leaks something about a document whose contents the
# encryption is supposed to protect.
class Attachment < ApplicationRecord
  belongs_to :document
  has_one_attached :ciphertext

  # 12 random bytes, base64 — the standard AES-GCM nonce length.
  validates :iv, presence: true, format: { with: /\A[A-Za-z0-9+\/=]{12,32}\z/, message: "is not a valid nonce" }
  validates :content_type, presence: true, inclusion: {
    in: %w[image/webp image/jpeg image/png application/pdf],
    message: "is not a supported file type"
  }
  validates :byte_size, presence: true,
                        numericality: { greater_than: 0, less_than_or_equal_to: 10.megabytes }
  validates :page_no, numericality: { greater_than: 0, less_than_or_equal_to: 100 }

  scope :ordered, -> { order(:page_no, :id) }

  def image? = content_type.start_with?("image/")
end
