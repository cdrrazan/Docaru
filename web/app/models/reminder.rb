# frozen_string_literal: true

# The record that a particular alert stage has already gone out.
class Reminder < ApplicationRecord
  belongs_to :document

  validates :kind, presence: true, uniqueness: { scope: :document_id }
  validates :scheduled_for, presence: true

  scope :sent, -> { where.not(sent_at: nil) }
end
