# frozen_string_literal: true

class DocumentsController < ApplicationController
  before_action :set_document, only: %i[show edit update destroy]

  # The vault itself: everything the household holds, findable rather than
  # ranked. Most of what is in here never expires and will never appear on the
  # dashboard, which is exactly why this screen has to exist — somebody in
  # another city looking for one certificate should not have to reason about
  # deadlines to find it.
  def index
    @query = params[:q].to_s.strip
    @member = household.members.find_by(id: params[:member_id])

    # Attachments are eager-loaded because the list shows a page count per row,
    # and this is the one screen guaranteed to hold every document a household
    # has.
    scope = household.documents.includes(:member, :attachments)
    scope = scope.matching(@query) if @query.present?
    scope = scope.where(member_id: @member.id) if @member

    # Alphabetical within each person rather than by urgency. This is a filing
    # cabinet on purpose; the queue is next door.
    @documents = scope.to_a.sort_by { |doc| [ doc.member.name, doc.title.downcase ] }
    @members = household.members.ordered
    @total = household.documents.count
  end

  def show
    @resolved = @document.resolved
    @timeline = @document.timeline
    @schedule = @document.schedule
    @chain = @document.chain
  end

  def new
    # Prefilled from a scan when the user came via the MRZ reader.
    @document = household.documents.new(prefill.merge(member_id: params[:member_id]))
    @document.issuing_country ||= default_country
  end

  def create
    @document = build_document

    unless household.can_add_document?
      @document.errors.add(:base, document_limit_message)
      return render :new, status: :unprocessable_entity
    end

    if @document.save
      redirect_to document_path(@document), notice: start_notice(@document)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @document.update(document_params)
      redirect_to document_path(@document), notice: start_notice(@document)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @document.destroy
    redirect_to dashboard_path, notice: "Removed."
  end

  private

  # Found through the household so another household's id reads as missing.
  def set_document
    @document = household.documents.find(params[:id])
  end

  def build_document
    member = household.members.find_by(id: document_params[:member_id])
    Document.new(document_params.merge(member: member))
  end

  # Only the three fields a scan can legitimately supply, so a crafted link
  # cannot prefill anything else.
  def prefill
    return {} unless params[:document]

    params.expect(document: [ :kind, :issuing_country, :expires_on ]).to_h.compact_blank
  end

  def document_params
    params.expect(document: [ :member_id, :kind, :issuing_country, :applying_from,
                              :expires_on, :issued_on, :label, :identifier, :notes ])
  end

  # Confirming the saved deadline immediately is the moment the product proves
  # itself: the user typed an expiry date and got back a date to act on.
  def start_notice(document)
    unless document.dated?
      return "Stored. No expiry date, so nothing to remind you about — add its scans and you can " \
             "reach it from anywhere."
    end

    return "Saved. We have no renewal rule for that document yet, so we will remind you before it expires." unless document.timeline

    case document.status
    when :overdue, :expired
      "Saved — and this one is already late. #{helpers.document_verdict(document)}"
    when :impossible
      "Saved. Note that this cannot be completed inside its renewal window."
    else
      "Saved. Start by #{document.start_by.strftime("%-d %B %Y")} — we will remind you."
    end
  end

  def default_country
    household.documents.order(created_at: :desc).first&.issuing_country
  end

  def document_limit_message
    "Your plan covers #{household.document_limit} documents. " \
      "Upgrade for unlimited — every reminder you already have keeps working either way."
  end
end
