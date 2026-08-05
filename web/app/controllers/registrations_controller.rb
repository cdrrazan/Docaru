# frozen_string_literal: true

class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_registration_path, alert: "Too many sign-up attempts. Try again in a few minutes." }

  def new
    @user = User.new
  end

  def create
    @user = User.register(**registration_params.to_h.symbolize_keys)

    if @user.persisted?
      start_new_session_for(@user)
      redirect_to dashboard_path, notice: "Welcome. Add your first document and we will work out when you need to start."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.expect(user: [ :email_address, :password, :password_confirmation, :name, :household_name ])
  end
end
