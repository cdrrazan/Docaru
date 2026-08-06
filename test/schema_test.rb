# frozen_string_literal: true

# Tests for the validator itself. A checker that only ever reports success is
# indistinguishable from no checker at all, so most of these assert that
# deliberately broken rules are actually rejected.
#
#   ruby test/schema_test.rb

require "minitest/autorun"
require "yaml"
require_relative "../lib/docaru/dataset"

SCHEMA = Docaru::SchemaValidator.from_file(
  File.join(Docaru::ROOT, "schema", "renewal-rule.schema.json")
)

VALID = YAML.safe_load(<<~YAML, permitted_classes: [Date], aliases: false)
  schema_version: 1
  country_code: NP
  document_kind: passport
  title: Test Document
  status: draft
  window_opens_days_before: 365
  window_closes_days_before: 0
  processing_days_domestic:
    typical: 10
    worst_case: 30
  required_documents:
    - item: Something you must bring
  cost:
    amount: 100
    currency: NPR
  authority_url: https://example.gov.np/
  lapse_consequence: Something specific and bad happens to you if you miss this deadline.
  source_urls:
    - https://example.gov.np/
YAML

def rule_with(overrides)
  Docaru::Rule.new(Docaru::Rule.normalise(VALID.merge(overrides)))
end

def errors_for(overrides)
  SCHEMA.validate(rule_with(overrides).data).map(&:to_s)
end

describe "the schema fixture itself" do
  it "validates, so failures below mean what they say" do
    _(SCHEMA.validate(VALID)).must_be_empty
  end
end

describe "schema enforcement" do
  it "rejects a missing required field" do
    data = VALID.reject { |k, _| k == "lapse_consequence" }
    _(SCHEMA.validate(data).map(&:to_s).join).must_match(/missing required property "lapse_consequence"/)
  end

  it "rejects an unknown field, so typos do not vanish silently" do
    _(errors_for("proccessing_days" => 5).join).must_match(/unknown property "proccessing_days"/)
  end

  it "rejects a document_kind outside the closed enum" do
    _(errors_for("document_kind" => "hunting_permit").join).must_match(/is not one of/)
  end

  it "rejects a lowercase country code" do
    _(errors_for("country_code" => "np").join).must_match(/does not match/)
  end

  it "rejects a non-https authority url" do
    _(errors_for("authority_url" => "http://example.gov.np/").join).must_match(/does not match/)
  end

  it "rejects a string where an integer belongs" do
    _(errors_for("window_opens_days_before" => "365").join).must_match(/expected integer, got string/)
  end

  it "rejects a duration missing worst_case" do
    _(errors_for("processing_days_domestic" => { "typical" => 10 }).join)
      .must_match(/missing required property "worst_case"/)
  end

  it "rejects an out-of-range number" do
    _(errors_for("window_opens_days_before" => 99_999).join).must_match(/must be <= 36500/)
  end

  it "rejects an empty required_documents list" do
    _(errors_for("required_documents" => []).join).must_match(/at least 1 item/)
  end

  it "rejects a rule with no sources at all" do
    _(errors_for("source_urls" => []).join).must_match(/at least 1 item/)
  end

  it "requires provenance when a rule claims to be verified" do
    joined = errors_for("status" => "verified").join
    _(joined).must_match(/verified_on/)
    _(joined).must_match(/verified_by/)
  end

  it "accepts a verified rule that names a date and a person" do
    _(errors_for("status" => "verified", "verified_on" => "2026-01-15", "verified_by" => "cdrrazan"))
      .must_be_empty
  end

  it "validates inside abroad_overrides rather than trusting them" do
    _(errors_for("abroad_overrides" => { "GB" => { "processing_days" => { "typical" => 1 } } }).join)
      .must_match(%r{/abroad_overrides/GB/processing_days: missing required property "worst_case"})
  end

  it "rejects an override key that is not a country code" do
    _(errors_for("abroad_overrides" => { "United Kingdom" => { "appointment_required" => true } }).join)
      .must_match(/does not match/)
  end

  it "rejects an empty override" do
    _(errors_for("abroad_overrides" => { "GB" => {} }).join).must_match(/at least 1 propert/)
  end
end

describe "override resolution" do
  let(:rule) do
    rule_with(
      "processing_days_abroad" => { "typical" => 40, "worst_case" => 60 },
      "abroad_overrides" => {
        "GB" => { "processing_days" => { "typical" => 50, "worst_case" => 80 } },
        "QA" => { "appointment_required" => true }
      }
    )
  end

  it "uses domestic timings for the domestic context" do
    _(rule.resolve("domestic").processing["worst_case"]).must_equal 30
  end

  it "falls back to the generic abroad timing when an override is silent" do
    _(rule.resolve("QA").processing["worst_case"]).must_equal 60
  end

  it "prefers the override where one is given" do
    _(rule.resolve("GB").processing["worst_case"]).must_equal 80
  end

  it "inherits base fields the override does not mention" do
    _(rule.resolve("GB").authority_url).must_equal "https://example.gov.np/"
  end

  it "merges additional_documents onto the base list" do
    r = rule_with("abroad_overrides" => { "GB" => { "additional_documents" => [{ "item" => "Local residence proof" }] } })
    _(r.resolve("GB").required_documents.length).must_equal 2
    _(r.resolve("domestic").required_documents.length).must_equal 1
  end

  it "will not let a verified base launder an unverified branch" do
    r = rule_with(
      "status" => "verified", "verified_on" => "2026-01-15", "verified_by" => "cdrrazan",
      "abroad_overrides" => { "GB" => { "status" => "draft" } }
    )
    _(r.resolve("domestic").status).must_equal "verified"
    _(r.resolve("GB").status).must_equal "draft"
  end

  it "produces one context per origin, plus domestic" do
    _(rule.contexts).must_equal ["domestic", "GB", "QA"]
  end
end

describe "timeline arithmetic" do
  it "adds processing, the slowest prerequisite, and the buffer" do
    r = rule_with(
      "buffer_days" => 14,
      "required_documents" => [
        { "item" => "Fast thing", "obtain_lead_days" => 3 },
        { "item" => "Slow thing", "obtain_lead_days" => 40 }
      ]
    )
    _(r.resolve("domestic").timeline.required_lead_days).must_equal(30 + 40 + 14)
  end

  it "plans against worst_case, not typical" do
    t = rule_with("buffer_days" => 0).resolve("domestic").timeline
    _(t.required_lead_days).must_equal 30
  end

  it "ignores optional prerequisites in the headline number" do
    r = rule_with(
      "buffer_days" => 0,
      "required_documents" => [
        { "item" => "Mandatory", "obtain_lead_days" => 5 },
        { "item" => "Only sometimes", "obtain_lead_days" => 200, "optional" => true }
      ]
    )
    _(r.resolve("domestic").timeline.required_lead_days).must_equal 35
    _(r.resolve("domestic").conditional_prerequisites.length).must_equal 1
  end

  it "never starts before the window opens" do
    r = rule_with("window_opens_days_before" => 20, "buffer_days" => 0)
    t = r.resolve("domestic").timeline
    _(t.required_lead_days).must_equal 30
    _(t.start_days_before_expiry).must_equal 20
  end

  it "flags a process that cannot finish inside its own window" do
    t = rule_with("window_opens_days_before" => 20, "buffer_days" => 0).resolve("domestic").timeline
    _(t.feasible?).must_equal false
    _(t.shortfall_days).must_equal 10
  end

  it "treats a generous window as feasible" do
    t = rule_with("window_opens_days_before" => 365, "buffer_days" => 0).resolve("domestic").timeline
    _(t.feasible?).must_equal true
    _(t.shortfall_days).must_equal 0
  end

  it "recognises when a grace period absorbs the shortfall" do
    t = rule_with(
      "window_opens_days_before" => 20,
      "window_closes_days_before" => -60,
      "buffer_days" => 0
    ).resolve("domestic").timeline
    _(t.covered_by_grace?).must_equal true
    _(t.verdict).must_match(/Late renewal is permitted/)
  end

  it "says so plainly when there is no grace at all" do
    t = rule_with("window_opens_days_before" => 20, "buffer_days" => 0).resolve("domestic").timeline
    _(t.verdict).must_match(/no grace period/)
  end

  it "computes a start date from an expiry date" do
    t = rule_with("buffer_days" => 14).resolve("domestic").timeline
    _(t.start_by("2026-12-31").to_s).must_equal "2026-11-17"
  end
end

describe "the shipped dataset" do
  let(:dataset) { Docaru::Dataset.load }

  it "loads without YAML errors" do
    _(dataset.load_errors).must_be_empty
  end

  it "is not empty" do
    _(dataset.rules).wont_be_empty
  end

  it "validates every rule against the schema" do
    dataset.each do |rule|
      _(SCHEMA.validate(rule.data).map(&:to_s)).must_be_empty("#{rule.path} failed schema")
    end
  end

  it "gives every playbook a start-by verdict without raising" do
    dataset.playbooks.each { |p| _(p.timeline.verdict).wont_be_empty }
  end
end
