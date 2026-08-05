# frozen_string_literal: true

require "test_helper"

class SitemapTest < ActionDispatch::IntegrationTest
  test "lists every playbook the dataset produces" do
    get sitemap_path

    assert_response :success
    assert_equal "application/xml", response.media_type

    locations = css_select("loc").map(&:text)

    assert_equal RuleCatalog.playbooks.size + 3, locations.size
    assert_includes locations, playbook_url(country_code: "np", document_kind: "passport")
    assert_includes locations, origin_playbook_url(country_code: "np", document_kind: "passport", origin: "gb")
    assert_includes locations, calculator_url
  end

  # Generated from the dataset rather than maintained by hand, so a merged rule
  # publishes its pages without anybody remembering to list them.
  test "grows with the dataset rather than with a checklist" do
    get sitemap_path

    assert_equal css_select("loc").map(&:text).uniq.size, css_select("loc").size
  end

  # A sitemap that advertises pages the crawler is then refused is worse than no
  # sitemap: it spends the crawl budget teaching Google to distrust the file.
  test "advertises nothing that does not resolve" do
    get sitemap_path

    css_select("loc").map(&:text).each do |url|
      get URI.parse(url).path

      assert_response :success, "#{url} is in the sitemap but did not return 200"
    end
  end

  test "carries no private plane urls" do
    get sitemap_path

    locations = css_select("loc").map(&:text)

    assert_empty locations.grep(/dashboard|documents|members|session/)
  end
end
