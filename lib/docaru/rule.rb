# frozen_string_literal: true

require "yaml"
require "date"

module Docaru
  # One rule file, plus the resolution of its per-origin overrides.
  class Rule
    attr_reader :data, :path

    def initialize(data, path: nil)
      @data = data
      @path = path
    end

    def self.load(path)
      raw = YAML.safe_load(File.read(path, encoding: "UTF-8"), permitted_classes: [Date], aliases: false)
      new(normalise(raw), path: path)
    end

    # Psych turns an unquoted 2026-01-31 into a Date. Contributors should not have
    # to know that, so dates are accepted either way and normalised to ISO strings
    # before the schema ever sees them.
    def self.normalise(node)
      case node
      when Date then node.strftime("%Y-%m-%d")
      when Hash then node.transform_values { |v| normalise(v) }
      when Array then node.map { |v| normalise(v) }
      else node
      end
    end

    def country_code = data["country_code"]
    def document_kind = data["document_kind"]
    def title = data["title"]
    def status = data["status"]
    def slug = "#{country_code.downcase}-#{document_kind.tr("_", "-")}"
    def origins = (data["abroad_overrides"] || {}).keys.sort

    # Every context this rule can be rendered for: applying at home, plus each
    # origin country an override describes. Each is one playbook page.
    def contexts = [Context::DOMESTIC, *origins]

    def resolve(context)
      Resolved.new(self, context)
    end

    module Context
      DOMESTIC = "domestic"
    end

    # A rule viewed from one place. Overrides win field by field; anything the
    # override is silent about falls back to the base rule.
    class Resolved
      attr_reader :rule, :context

      def initialize(rule, context)
        @rule = rule
        @context = context
        @override = context == Context::DOMESTIC ? {} : (rule.data["abroad_overrides"] || {}).fetch(context, {})
      end

      def domestic? = context == Context::DOMESTIC

      def processing
        @override["processing_days"] ||
          (domestic? ? rule.data["processing_days_domestic"] : rule.data["processing_days_abroad"]) ||
          rule.data["processing_days_domestic"]
      end

      def cost = @override["cost"] || rule.data["cost"]
      def authority_url = @override["authority_url"] || rule.data["authority_url"]

      def appointment_required?
        @override.fetch("appointment_required", rule.data["appointment_required"])
      end

      def required_documents
        rule.data.fetch("required_documents", []) + @override.fetch("additional_documents", [])
      end

      # An override cannot be more trustworthy than the base rule it inherits from:
      # a verified base with an unchecked branch is still unchecked here.
      def status
        [rule.status, @override["status"] || rule.status].include?("draft") ? "draft" : "verified"
      end

      def verified_on = @override["verified_on"] || rule.data["verified_on"]
      def verified_by = @override["verified_by"] || rule.data["verified_by"]
      def draft? = status == "draft"

      def source_urls
        (Array(rule.data["source_urls"]) + Array(@override["source_urls"])).uniq
      end

      def notes
        [rule.data["notes"], @override["notes"]].compact.reject(&:empty?)
      end

      def buffer_days = rule.data.fetch("buffer_days", 14)
      def window_opens_days_before = rule.data["window_opens_days_before"]
      def window_closes_days_before = rule.data["window_closes_days_before"]

      # Grace after expiry during which this still counts as a renewal.
      def grace_days
        closes = window_closes_days_before
        closes.negative? ? -closes : 0
      end

      # The prerequisite that sets the pace. Optional items are excluded from the
      # headline number and surfaced separately, because they apply to some
      # applicants and not others.
      def slowest_prerequisite
        required_documents
          .reject { |d| d["optional"] }
          .select { |d| d["obtain_lead_days"].to_i.positive? }
          .max_by { |d| d["obtain_lead_days"] }
      end

      def conditional_prerequisites
        required_documents
          .select { |d| d["optional"] && d["obtain_lead_days"].to_i.positive? }
          .sort_by { |d| -d["obtain_lead_days"] }
      end

      def prerequisite_lead_days = slowest_prerequisite&.fetch("obtain_lead_days").to_i

      # Requirements that are themselves dated documents in the dataset. These
      # are the edges of the dependency graph, and the reason a renewal can be
      # blocked by a deadline nobody was watching.
      def prerequisite_rules
        required_documents.filter_map do |doc|
          ref = doc["satisfied_by"]
          next unless ref

          { requirement: doc, country_code: ref["country_code"], document_kind: ref["document_kind"] }
        end
      end

      def timeline = Timeline.new(self)

      def label
        domestic? ? "in #{rule.country_code}" : "from #{context}"
      end
    end
  end
end
