# frozen_string_literal: true

require "test_helper"

class PlaybooksControllerTest < ActionDispatch::IntegrationTest
  test "index lists every document" do
    get playbooks_path

    assert_response :success
    assert_select "h1", "Renewal playbooks"
    assert_select "a", text: "Nepali e-Passport"
  end

  test "shows the domestic playbook" do
    get playbook_path(country_code: "np", document_kind: "passport")

    assert_response :success
    assert_select "h1", /Nepali e-Passport renewal in Nepal/
  end

  test "shows a per-origin playbook" do
    get origin_playbook_path(country_code: "np", document_kind: "passport", origin: "gb")

    assert_response :success
    assert_select "h1", /from the United Kingdom/
  end

  # The whole product is this number. If it stops appearing, nothing else matters.
  test "leads with the start-by date" do
    get playbook_path(country_code: "np", document_kind: "passport")

    assert_select ".answer .headline", /Start \d+ days before it expires/
  end

  test "warns prominently when the process cannot fit its own window" do
    get playbook_path(country_code: "np", document_kind: "drivers-licence")

    assert_response :success
    assert_select ".answer-warn"
    assert_select ".banner-warn", /window is shorter than the process/
  end

  test "marks unverified rules as unverified" do
    get playbook_path(country_code: "np", document_kind: "passport")

    assert_select ".banner-draft", /unverified/i
  end

  test "renders the prerequisite lead time that drives the date" do
    get origin_playbook_path(country_code: "np", document_kind: "vehicle-registration", origin: "us")

    assert_response :success
    assert_select "td", /Power of attorney/
  end

  test "unknown document returns not found rather than an error" do
    get playbook_path(country_code: "np", document_kind: "hunting-permit")

    assert_response :not_found
  end

  test "unknown country returns not found" do
    get playbook_path(country_code: "zz", document_kind: "passport")

    assert_response :not_found
  end

  # An origin with no override is still a real question — somebody renewing from
  # Germany gets the generic abroad timings rather than being turned away.
  test "an origin with no override still renders, on the abroad timings" do
    get origin_playbook_path(country_code: "np", document_kind: "passport", origin: "de")

    assert_response :success
    assert_select "h1", /from Germany/
  end

  # Every country in the standard renders, not only the fourteen the picker used
  # to offer. Kenya has no override and never had one; the page is still a real
  # answer for somebody renewing a Nepali passport from Nairobi.
  test "any country in ISO 3166-1 renders" do
    get origin_playbook_path(country_code: "np", document_kind: "passport", origin: "ke")

    assert_response :success
    assert_select "h1", /from Kenya/
  end

  # The route matches any two letters. Without this the domestic page was served
  # at 676 addresses per document, and crawlers were left to work out which one
  # was real.
  test "an origin that is not a country returns not found" do
    get origin_playbook_path(country_code: "np", document_kind: "passport", origin: "zz")

    assert_response :not_found
  end

  # Serving a page and indexing it are separate decisions, and widening the
  # country list made the difference matter: an origin without an override
  # renders the generic abroad timings, so there is one substantive page and
  # about two hundred addresses carrying it. The one with an override is a
  # distinct answer and stays indexable.
  test "an origin with an override is indexable" do
    get origin_playbook_path(country_code: "np", document_kind: "passport", origin: "gb")

    assert_select "meta[name=robots]", count: 0
  end

  test "an origin with no override is served but not indexed" do
    get origin_playbook_path(country_code: "np", document_kind: "passport", origin: "ke")

    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
  end

  test "the domestic playbook is indexable" do
    get playbook_path(country_code: "np", document_kind: "passport")

    assert_select "meta[name=robots]", count: 0
  end

  # Not merely a duplicate URL: it rendered "renewal from Nepal" against the
  # abroad processing times, which is a wrong answer for somebody standing in
  # Kathmandu.
  test "applying from the issuing country redirects to the domestic playbook" do
    get origin_playbook_path(country_code: "np", document_kind: "passport", origin: "np")

    assert_redirected_to playbook_path(country_code: "np", document_kind: "passport")
    assert_response :moved_permanently
  end

  test "every playbook declares itself canonical" do
    get origin_playbook_path(country_code: "np", document_kind: "passport", origin: "gb")

    assert_select "link[rel=canonical][href=?]",
                  origin_playbook_url(country_code: "np", document_kind: "passport", origin: "gb")
  end

  # These links get pasted into forum threads; without a card they render as a
  # bare URL. The squish matters — the description is written as a wrapped ERB
  # block, and a newline inside the attribute truncates the card.
  test "playbooks carry a social card with single-line content" do
    get origin_playbook_path(country_code: "np", document_kind: "passport", origin: "gb")

    description = css_select("meta[property='og:description']").first["content"]

    assert_match(/United Kingdom/, description)
    assert_no_match(/[\n\r]/, description)
    assert_select "meta[property='og:title'][content=?]",
                  "Nepali e-Passport renewal from the United Kingdom"
  end
end
