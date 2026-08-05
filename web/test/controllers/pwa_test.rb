# frozen_string_literal: true

require "test_helper"

class PwaTest < ActionDispatch::IntegrationTest
  test "serves a manifest describing this application" do
    get pwa_manifest_path

    assert_response :success
    assert_equal "application/json", response.media_type

    manifest = JSON.parse(response.body)

    assert_equal "Renewal playbooks", manifest["name"]
    assert_equal "standalone", manifest["display"]
    assert manifest["icons"].any?, "the manifest lists no icons"
  end

  # It shipped as the Rails default — name "Web", description "Web.",
  # theme_color "red" — and unrouted, so nothing ever rendered it.
  test "the manifest is not the generator boilerplate" do
    manifest = JSON.parse(get(pwa_manifest_path) && response.body)

    assert_not_equal "Web", manifest["name"]
    assert_not_equal "red", manifest["theme_color"]
  end

  test "every page offers the manifest" do
    get playbooks_path

    assert_select "link[rel=manifest][href=?]", pwa_manifest_path
  end

  test "serves the service worker at a root scope" do
    get pwa_service_worker_path

    assert_response :success
    assert_equal "text/javascript", response.media_type
    assert_equal "/service-worker", pwa_service_worker_path,
                 "the worker must sit at the root to claim a scope of /"
  end

  # The rule the worker exists to enforce. SECURITY.md is explicit that document
  # metadata is stored in the clear and is sensitive for a migrant; caching a
  # dashboard would write it to disk, where it outlives signing out and is
  # readable by whoever picks up the device next.
  test "the service worker caches by allowlist, never the private plane" do
    get pwa_service_worker_path

    # Scoped to the allowlist itself rather than the whole file. Naming a
    # private path elsewhere is fine — notificationclick opens /dashboard, which
    # is the point of the notification — but caching one never is.
    allowlist = response.body[/PUBLIC_PATHS\s*=\s*\[(.*?)\]/m, 1]

    assert allowlist, "the service worker no longer declares a PUBLIC_PATHS allowlist"
    assert_match(%r{/playbooks}, allowlist)

    %w[dashboard documents members attachments scans session push].each do |private_path|
      assert_no_match(/#{private_path}/, allowlist,
                      "#{private_path} is in the cache allowlist and must never be")
    end
  end

  test "the service worker refuses responses that carry a session" do
    get pwa_service_worker_path

    assert_match(/set-cookie/, response.body)
    assert_match(/private/, response.body)
  end
end
