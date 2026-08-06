#!/usr/bin/env ruby
# frozen_string_literal: true

# Using the dataset through its own library, with no intermediate file.
#
#   ruby examples/ruby/start_date.rb NP passport GB 2027-03-14
#
# Ruby 3.x and nothing else — no gems, no bundler, no network. This is the
# closest reading of the data available: Dataset.load parses rules/ directly,
# so a rule edited a second ago is a rule this sees.

require_relative "../../lib/docaru/dataset"
require "date"

country, kind, origin, expires_on = ARGV
abort "usage: start_date.rb <COUNTRY> <DOCUMENT_KIND> <FROM|domestic> <YYYY-MM-DD>" unless expires_on

dataset = Docaru::Dataset.load

rule = dataset.rules.find do |r|
  r.country_code == country.upcase && r.document_kind == kind.tr("-", "_")
end
abort "No rule for #{country}/#{kind}. Known: #{dataset.rules.map(&:slug).join(", ")}" unless rule

# An origin with no override still resolves — it falls back to the generic
# abroad timings. Falling back to *domestic* instead would hand somebody abroad
# a date months too late, which is the failure mode worth knowing about.
context = origin.casecmp?("domestic") ? Docaru::Rule::Context::DOMESTIC : origin.upcase
resolved = rule.resolve(context)
timeline = resolved.timeline

expiry = Date.parse(expires_on)
start_by = timeline.start_by(expiry)

puts "#{rule.title} — #{resolved.label}"
puts "  expires        #{expiry}"
puts "  start by       #{start_by}  (#{timeline.start_days_before_expiry} days before expiry)"
puts "  window opens   #{timeline.window_opens_on(expiry)}"
puts

# worst_case, never typical. A date derived from the median is correct for the
# median applicant and useless for everyone in the tail — and the tail is where
# a missed deadline costs somebody their legal status.
puts "  processing     #{timeline.processing_days} days worst case (#{timeline.typical_days} typical)"
puts "  prerequisites  #{timeline.prerequisite_days} days for the slowest one"
puts "  buffer         #{timeline.buffer_days} days"
puts "  total lead     #{timeline.required_lead_days} days"
puts

puts "  #{timeline.verdict}"

unless timeline.feasible?
  # Not an error. The data is right and the process is the problem, which is the
  # fact a reader most needs.
  puts "  projected finish #{timeline.projected_completion(expiry)} — " \
       "#{timeline.shortfall_days} days after it expires."
end

puts "  UNVERIFIED — no human has checked these figures against the authority." if resolved.draft?

exit(timeline.feasible? ? 0 : 2)
