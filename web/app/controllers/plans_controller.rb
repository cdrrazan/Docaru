# frozen_string_literal: true

class PlansController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    # Pricing is public, so the authentication filter is skipped — which also
    # skips resuming the session. `authenticated?` does the resuming, and
    # without it a signed-in visitor looks anonymous on their own pricing page.
    @household = household if authenticated?
  end

  # Opens a Paddle checkout and sends the buyer to it. The plan does not move
  # here: it moves when Paddle says the money arrived, on the webhook. A browser
  # that has been redirected back is evidence of nothing.
  def update
    return redirect_to plan_path, alert: unconfigured_message unless Paddle.configured?

    checkout = Paddle.create_checkout(
      household: household,
      email: current_user.email_address,
      success_url: dashboard_url,
      plan: requested_plan
    )

    redirect_to checkout, allow_other_host: true
  rescue Paddle::Error => e
    Rails.error.report(e, handled: true, context: { household_id: household.id })
    redirect_to plan_path, alert: "Could not open the checkout just now. Nothing was charged — please try again."
  end

  private

  # Whitelisted against what this instance can actually sell, so a hand-edited
  # form cannot open a checkout for a plan with no configured price — or, worse,
  # name a plan that is not a plan.
  def requested_plan
    candidate = params[:plan].to_s

    Paddle.sellable_plans.include?(candidate) ? candidate : "household"
  end

  def unconfigured_message
    "Billing is not switched on for this instance. Nothing was charged, and every reminder " \
      "you already have keeps working."
  end
end
