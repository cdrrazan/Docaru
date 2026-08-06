# frozen_string_literal: true

require_relative "rule"
require_relative "timeline"
require_relative "countries"
require_relative "schema_validator"

module Docaru
  ROOT = File.expand_path("../..", __dir__)

  # The whole public plane: every rule file, loaded once.
  class Dataset
    attr_reader :rules, :load_errors

    # Overridable so a deployed image can ship the rules anywhere it likes —
    # the self-hosted container puts them beside the app rather than one
    # directory up from it.
    def self.rules_dir
      ENV.fetch("DOCARU_RULES_DIR") { File.join(ROOT, "rules") }
    end

    def self.load(dir = rules_dir)
      rules = []
      errors = []

      Dir.glob(File.join(dir, "**", "*.yml")).sort.each do |path|
        rules << Rule.load(path)
      rescue Psych::Exception => e
        errors << [path, "not valid YAML: #{e.message}"]
      end

      new(rules, errors)
    end

    def initialize(rules, load_errors = [])
      @rules = rules
      @load_errors = load_errors
    end

    def countries = rules.map(&:country_code).uniq.sort
    def each(&) = rules.each(&)

    # Every (rule, context) pair — one playbook page each. This is the unit that
    # both the reader and the search engine care about: nobody searches for
    # "Nepali passport renewal", they search for "from the UK".
    def playbooks
      rules.flat_map { |rule| rule.contexts.map { |ctx| rule.resolve(ctx) } }
    end
  end
end
