# frozen_string_literal: true

# Registering and revoking the devices a reminder should reach.
#
# Scoped to the signed-in user rather than the household: a permission granted
# on one person's phone is theirs, and somebody else in the household should not
# be able to revoke it or enumerate it.
class PushSubscriptionsController < ApplicationController
  def create
    subscription = current_user.push_subscriptions.find_or_initialize_by(endpoint: params[:endpoint])
    subscription.assign_attributes(
      p256dh_key: params[:p256dh_key],
      auth_key: params[:auth_key],
      user_agent: request.user_agent&.truncate(255),
      # Re-subscribing after a revocation is a fresh grant, not a resurrection
      # of the old one.
      expired_at: nil
    )

    if subscription.save
      head :created
    else
      render json: { errors: subscription.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    current_user.push_subscriptions.where(endpoint: params[:endpoint]).destroy_all
    head :no_content
  end
end
