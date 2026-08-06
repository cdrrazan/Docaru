# frozen_string_literal: true

# Where a document's renewal depends on another document the household also
# holds — and whether that dependency is about to cause a problem.
#
# This is the thing a product that stores only expiry dates cannot do. Nepal
# will not renew a vehicle registration without current third-party insurance.
# Both have their own deadline, and the failure is not missing either one: it is
# that the insurance lapses three weeks before the registration renewal needs
# it, so the registration slips too, and the fine compounds while nobody
# understands why. The dataset already records the dependency; this joins it to
# what the household actually owns.
class PrerequisiteChain
  Link = Struct.new(:requirement, :country_code, :document_kind, :document, :status, keyword_init: true) do
    def blocking? = %i[expires_first also_due].include?(status)
    def known? = document.present?
  end

  attr_reader :document

  def initialize(document)
    @document = document
  end

  def links
    @links ||= begin
      # A dependency only bites when there is a renewal to block. A stored
      # document with no expiry is never being renewed, so nothing can be in
      # its way.
      resolved = document.dated? ? document.resolved : nil
      resolved ? resolved.prerequisite_rules.map { |ref| build_link(ref) } : []
    end
  end

  def any? = links.any?
  def blocking = links.select(&:blocking?)
  def blocking? = blocking.any?
  def untracked = links.reject(&:known?)

  private

  def build_link(ref)
    prerequisite = find_document(ref)

    Link.new(
      requirement: ref[:requirement],
      country_code: ref[:country_code],
      document_kind: ref[:document_kind],
      document: prerequisite,
      status: status_for(prerequisite)
    )
  end

  # Prefer the same person's copy — a household can hold several of the same
  # kind, and the one that matters is the one belonging to whoever owns the
  # dependent document.
  def find_document(ref)
    candidates = document.member.household.documents
                         .where(kind: ref[:document_kind], issuing_country: ref[:country_code])
                         .where.not(id: document.id)

    candidates.find { |candidate| candidate.member_id == document.member_id } || candidates.first
  end

  def status_for(prerequisite)
    return :missing unless prerequisite

    needed_by = document.start_by || document.expires_on

    # Held, but with no expiry recorded — so we know it exists and cannot say
    # whether it will still be valid. Reported as its own state rather than
    # waved through as `:ok`, because "we have no idea" and "you are fine" are
    # different things to tell somebody planning a renewal.
    return :undated unless prerequisite.dated?

    # The prerequisite lapses before the dependent renewal even begins, so the
    # renewal is blocked before it starts.
    return :expires_first if prerequisite.expires_on < needed_by

    # The prerequisite has its own renewal to run, and it has to happen first.
    return :also_due if prerequisite.start_by && prerequisite.start_by <= needed_by

    :ok
  end
end
