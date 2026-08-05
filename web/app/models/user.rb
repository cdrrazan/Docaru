class User < ApplicationRecord
  has_secure_password
  belongs_to :household
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP, message: "does not look like an email address" }
  validates :name, length: { maximum: 120 }, allow_blank: true
  # has_secure_password checks presence and confirmation but not length.
  validates :password, length: { minimum: 8 }, allow_nil: true

  # Signing up creates the household alongside the user. Asking somebody to name
  # a household before they have entered a single document is a form standing in
  # front of any delivered value, so it gets a sensible default they can change
  # later.
  def self.register(email_address:, password:, password_confirmation: nil, name: nil, household_name: nil)
    household = Household.new(name: household_name.presence || default_household_name(email_address, name))
    user = household.users.build(
      email_address: email_address,
      password: password,
      password_confirmation: password_confirmation,
      name: name
    )

    household.save
    user
  end

  def self.default_household_name(email_address, name)
    return "#{name.to_s.split.first}'s household" if name.present?

    local = email_address.to_s.split("@").first.presence || "My"
    "#{local.capitalize}'s household"
  end

  def display_name = name.presence || email_address
end
