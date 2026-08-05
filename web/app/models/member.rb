# frozen_string_literal: true

# A person documents belong to. Not necessarily a person who can log in: the
# wedge this product is aimed at includes people managing a parent's paperwork
# from another country, and that parent never signs up for anything.
class Member < ApplicationRecord
  belongs_to :household
  has_many :documents, dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }
  validates :relationship, length: { maximum: 60 }, allow_blank: true

  scope :ordered, -> { order(:name) }

  def display_name
    relationship.present? ? "#{name} (#{relationship})" : name
  end
end
