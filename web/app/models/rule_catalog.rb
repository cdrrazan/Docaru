# frozen_string_literal: true

# The application's window onto the public rules dataset.
#
# The dataset is flat files, not database rows, and that is deliberate: it is
# public, versioned in git, and edited by pull request. Loading it into
# ActiveRecord would mean a migration every time somebody corrects a fee, and
# would put user data and public data in the same store — the one thing the
# architecture is trying to keep apart.
class RuleCatalog
  class UnknownRule < StandardError; end

  class << self
    # Reloaded on every call in development so editing a YAML file shows up on
    # refresh; cached everywhere else, because parsing the whole dataset on each
    # request would be silly.
    def dataset
      return Renewaru::Dataset.load if Rails.env.development?

      @dataset ||= Renewaru::Dataset.load
    end

    def reload!
      @dataset = nil
      dataset
    end

    def rules = dataset.rules
    def playbooks = dataset.playbooks
    def countries = dataset.countries

    def any? = rules.any?

    # Document kinds that actually have a rule, which is what the forms offer.
    # Offering a kind with no rule would mean promising a start-by date we
    # cannot compute.
    def document_kinds
      rules.map(&:document_kind).uniq.sort
    end

    def kinds_for(country_code)
      rules.select { |r| r.country_code == country_code.to_s.upcase }
           .sort_by(&:title)
    end

    def find(country_code, document_kind)
      kind = document_kind.to_s.tr("-", "_")
      rules.find do |rule|
        rule.country_code == country_code.to_s.upcase && rule.document_kind == kind
      end
    end

    def find!(country_code, document_kind)
      find(country_code, document_kind) ||
        raise(UnknownRule, "no rule for #{country_code}/#{document_kind}")
    end

    # A rule seen from one place. `context` is either "domestic" or the ISO code
    # of the country the applicant is applying from.
    def resolve(country_code, document_kind, context = Renewaru::Rule::Context::DOMESTIC)
      rule = find!(country_code, document_kind)
      normalised = normalise_context(rule, context)
      rule.resolve(normalised)
    end

    # An origin with no override still resolves — it just falls back to the
    # generic abroad timings. Silently returning the domestic view instead would
    # give someone abroad a date that is months too late.
    def normalise_context(rule, context)
      value = context.to_s
      return Renewaru::Rule::Context::DOMESTIC if value.blank? || value.casecmp?("domestic")

      code = value.upcase
      return code if rule.origins.include?(code)
      return code if Renewaru::Countries::NAMES.key?(code)

      Renewaru::Rule::Context::DOMESTIC
    end

    # Origins we can say something specific about, for the "applying from"
    # selector. Domestic is always first because it is the simple case.
    def origins_for(rule)
      [ Renewaru::Rule::Context::DOMESTIC, *rule.origins ]
    end
  end
end
