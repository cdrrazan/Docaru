# frozen_string_literal: true

class MembersController < ApplicationController
  before_action :set_member, only: %i[edit update destroy]

  def index
    @members = household.members.ordered
  end

  def new
    @member = household.members.new
  end

  def create
    @member = household.members.new(member_params)

    unless household.can_add_member?
      @member.errors.add(:base, member_limit_message)
      return render :new, status: :unprocessable_entity
    end

    if @member.save
      redirect_to members_path, notice: "#{@member.name} added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @member.update(member_params)
      redirect_to members_path, notice: "Saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    count = @member.documents.count
    @member.destroy
    redirect_to members_path,
                notice: count.zero? ? "#{@member.name} removed." : "#{@member.name} and #{helpers.pluralize(count, "document")} removed."
  end

  private

  # Scoped through the household rather than looked up globally: a member id
  # from another household must read as missing, not as forbidden.
  def set_member
    @member = household.members.find(params[:id])
  end

  def member_params
    params.expect(member: [ :name, :relationship ])
  end

  def member_limit_message
    "Your plan covers #{helpers.pluralize(household.member_limit, "person")}. " \
      "Upgrade to track documents for the whole household."
  end
end
