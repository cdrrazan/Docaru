# frozen_string_literal: true

class DashboardController < ApplicationController
  def show
    @members = household.members.ordered
    # Sorted by trouble, not by date added: this screen is a queue of what to do
    # next, not a filing cabinet.
    @documents = household.documents.includes(:member).to_a.sort_by(&:sort_key)
    @needs_attention = @documents.reject { |doc| doc.status == :ahead }

    # A renewal blocked by another document the household holds. This is the
    # warning nobody else can produce, so it gets its own place on the page
    # rather than being buried inside a detail view nobody opens.
    @blocked = @documents.filter_map do |doc|
      chain = doc.chain
      [ doc, chain ] if chain.blocking?
    end
  end
end
