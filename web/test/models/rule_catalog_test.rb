# frozen_string_literal: true

require "test_helper"

class RuleCatalogTest < ActiveSupport::TestCase
  test "loads the shipped dataset" do
    assert RuleCatalog.any?
    assert_includes RuleCatalog.countries, "NP"
  end

  test "finds a rule by country and kind" do
    rule = RuleCatalog.find("NP", "passport")

    assert_equal "NP", rule.country_code
    assert_equal "passport", rule.document_kind
  end

  test "accepts the dashed url form of a document kind" do
    assert_equal RuleCatalog.find("NP", "police_clearance"),
                 RuleCatalog.find("np", "police-clearance")
  end

  test "find! raises for an unknown rule rather than returning nil" do
    assert_raises(RuleCatalog::UnknownRule) { RuleCatalog.find!("ZZ", "passport") }
  end

  test "resolves the domestic context by default" do
    resolved = RuleCatalog.resolve("NP", "passport")

    assert_predicate resolved, :domestic?
  end

  test "resolves a per-origin override" do
    domestic = RuleCatalog.resolve("NP", "passport")
    from_gb = RuleCatalog.resolve("NP", "passport", "GB")

    assert_equal "GB", from_gb.context
    assert_not_equal domestic.processing["worst_case"], from_gb.processing["worst_case"]
  end

  # Someone abroad in a country we have no override for must not be shown the
  # domestic timings — those are months too optimistic and would produce a
  # start-by date that arrives after it is useful.
  test "an origin without an override still uses abroad timings" do
    resolved = RuleCatalog.resolve("NP", "passport", "DE")

    assert_equal "DE", resolved.context
    assert_not_predicate resolved, :domestic?
    assert_equal RuleCatalog.find("NP", "passport").data["processing_days_abroad"],
                 resolved.processing
  end

  test "falls back to domestic for a context that is not a country" do
    assert_predicate RuleCatalog.resolve("NP", "passport", "nonsense"), :domestic?
    assert_predicate RuleCatalog.resolve("NP", "passport", ""), :domestic?
  end

  test "origins_for always leads with domestic" do
    rule = RuleCatalog.find("NP", "passport")

    assert_equal Docaru::Rule::Context::DOMESTIC, RuleCatalog.origins_for(rule).first
  end

  test "every shipped rule can be resolved and timed in every context" do
    RuleCatalog.rules.each do |rule|
      RuleCatalog.origins_for(rule).each do |context|
        timeline = rule.resolve(context).timeline

        assert_kind_of Integer, timeline.required_lead_days
        assert_not_empty timeline.verdict
      end
    end
  end
end
