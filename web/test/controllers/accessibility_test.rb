# frozen_string_literal: true

require "test_helper"

# These assert the parts of the markup a keyboard or a screen reader depends on
# and a browser will never complain about. They are cheap, and they fail loudly
# when a new page is added that forgets them.
class AccessibilityTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  PUBLIC_PAGES = %w[/ /when-to-start /playbooks /playbooks/np/passport /playbooks/np/passport/from-gb].freeze

  test "every page offers a skip link into the content" do
    (PUBLIC_PAGES + %w[/dashboard]).each do |path|
      get path

      assert_select "a.skip[href=?]", "#content", { count: 1 }, "#{path} has no skip link"
      assert_select "main#content", { count: 1 }, "#{path} has no skip target"
    end
  end

  test "the main navigation is labelled" do
    get "/"

    assert_select "nav[aria-label=?]", "Main"
  end

  # A scrollable box is only scrollable by keyboard if it can hold focus, and
  # these hold the tables that carry the actual answer.
  test "scrollable tables are reachable and named" do
    get "/playbooks/np/passport"

    assert_select "div.scroll[tabindex=?][role=?]", "0", "region"
    assert_select "div.scroll[aria-label]"
  end

  test "table headers declare what they head" do
    get "/playbooks/np/passport"

    assert_select "thead th:not([scope])", false, "a column header is missing scope"
  end

  test "the dashboard table is scoped and captioned" do
    get "/dashboard"

    assert_select "table caption"
    assert_select "thead th[scope=?]", "col", 4
  end

  # A flash arrives after a redirect, by which point the page is already being
  # read. Without a live region it is never announced at all.
  # An alert interrupts rather than waiting its turn: "try another password" is
  # not a footnote to whatever is being read out.
  test "flash alerts announce themselves assertively" do
    post session_path, params: { email_address: "one@example.com", password: "wrong" }
    follow_redirect!

    assert_select "div.flash.flash-alert[role=?][aria-live=?]", "alert", "assertive"
  end

  test "flash notices announce themselves politely" do
    post members_path, params: { member: { name: "Buwa", relationship: "Father" } }
    follow_redirect!

    assert_select "div.flash[role=?][aria-live=?]", "status", "polite"
  end

  test "validation summaries are announced and focusable" do
    post members_path, params: { member: { name: "" } }

    assert_select "div.errors[role=?][tabindex=?]", "alert", "-1"
  end

  test "the vault reports its state to a screen reader" do
    document = documents(:passport)

    get document_path(document)

    assert_select "[data-vault-target=status][role=status][aria-live=?]", "polite"
  end
end
