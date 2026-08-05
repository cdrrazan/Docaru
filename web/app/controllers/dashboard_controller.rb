# frozen_string_literal: true

class DashboardController < ApplicationController
  def show
    @members = household.members.ordered
    # Sorted by trouble, not by date added: this screen is a queue of what to do
    # next, not a filing cabinet.
    @documents = household.documents.includes(:member).to_a.sort
    @needs_attention = @documents.reject { |doc| doc.status == :ahead }
  end
end
