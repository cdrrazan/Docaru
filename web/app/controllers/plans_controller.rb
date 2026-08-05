# frozen_string_literal: true

class PlansController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    # Pricing is public, so the authentication filter is skipped — which also
    # skips resuming the session. `authenticated?` does the resuming, and
    # without it a signed-in visitor looks anonymous on their own pricing page.
    @household = household if authenticated?
  end

  # Deliberately not a checkout. No payment processor is wired up yet, and
  # pretending otherwise with a dead button would be worse than saying so.
  def update
    household.update!(plan: "household")
    redirect_to dashboard_path, notice: "Switched to the household plan."
  end
end
