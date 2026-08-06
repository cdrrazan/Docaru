# frozen_string_literal: true

class DashboardController < ApplicationController
  def show
    @members = household.members.ordered
    # Sorted by trouble, not by date added: this screen is a queue of what to do
    # next. The filing cabinet is DocumentsController#index.
    @documents = household.documents.includes(:member).to_a.sort_by(&:sort_key)

    # Only documents with a deadline can want anything. Most of a vault never
    # will, and listing a birth certificate under "needs attention" would train
    # people to ignore the section that matters.
    @needs_attention = @documents.select(&:needs_attention?)
    @watching = @documents.select { |doc| doc.dated? && !doc.needs_attention? }
    @stored = @documents.reject(&:dated?)

    # A renewal blocked by another document the household holds. This is the
    # warning nobody else can produce, so it gets its own place on the page
    # rather than being buried inside a detail view nobody opens.
    @blocked = @documents.filter_map do |doc|
      chain = doc.chain
      [ doc, chain ] if chain.blocking?
    end
  end
end
