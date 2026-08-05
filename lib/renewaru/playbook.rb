# frozen_string_literal: true

require "cgi"

module Renewaru
  # Renders one resolved rule as a standalone HTML page.
  #
  # Server-rendered, no JavaScript, no external requests. That is a deliberate
  # constraint rather than minimalism for its own sake: organic search is the one
  # acquisition channel that compounds, and a page a crawler cannot read does not
  # exist. Every fact on the page is in the HTML the server sends.
  class Playbook
    COUNTRY_NAMES = {
      "NP" => "Nepal", "GB" => "the United Kingdom", "US" => "the United States",
      "AU" => "Australia", "QA" => "Qatar", "AE" => "the United Arab Emirates",
      "MY" => "Malaysia", "KR" => "South Korea", "JP" => "Japan", "IN" => "India",
      "CA" => "Canada", "DE" => "Germany", "PT" => "Portugal", "SA" => "Saudi Arabia"
    }.freeze

    ADJECTIVES = { "NP" => "Nepali" }.freeze

    attr_reader :resolved, :repo_url

    def initialize(resolved, repo_url:)
      @resolved = resolved
      @repo_url = repo_url
    end

    def rule = resolved.rule
    def timeline = resolved.timeline

    def self.country_name(code) = COUNTRY_NAMES.fetch(code, code)

    def place
      resolved.domestic? ? "inside #{self.class.country_name(rule.country_code)}" : "from #{self.class.country_name(resolved.context)}"
    end

    # Phrased to match how the question is actually typed into a search box:
    # "Nepali e-Passport renewal from the United Kingdom".
    def heading = "#{rule.title} renewal #{place}"

    # The query this page is trying to be the answer to.
    def description
      if timeline.feasible?
        "How long #{rule.title} renewal takes #{place}, what it costs, what you need, " \
          "and the date you have to start by: #{timeline.start_days_before_expiry} days before expiry."
      else
        "How long #{rule.title} renewal takes #{place}, what it costs, what you need, and why " \
          "it cannot be completed before expiry #{place}."
      end
    end

    def path
      base = File.join(rule.country_code.downcase, rule.document_kind.tr("_", "-"))
      resolved.domestic? ? base : File.join(base, "from-#{resolved.context.downcase}")
    end

    def source_file
      "#{repo_url}/blob/main/#{rule.path.to_s.sub(%r{\A.*?/rules/}, "rules/")}"
    end

    def e(text) = CGI.escapeHTML(text.to_s)

    def render
      root = "../" * (path.count("/") + 1)
      <<~HTML
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>#{e(heading)}</title>
        <meta name="description" content="#{e(description)}">
        <link rel="stylesheet" href="#{root}style.css">
        </head>
        <body>
        <header class="bar"><a href="#{root}index.html">&larr; All renewal playbooks</a></header>
        <main>
        <h1>#{e(heading)}</h1>
        <p class="lede">#{e(description)}</p>
        #{draft_banner}
        #{answer_box}
        #{breakdown}
        #{window_section}
        #{cost_section}
        #{documents_section}
        #{consequence_section}
        #{notes_section}
        #{provenance}
        </main>
        </body>
        </html>
      HTML
    end

    private

    def draft_banner
      return "" unless resolved.draft?

      <<~HTML
        <div class="banner banner-draft">
          <strong>These figures are unverified.</strong>
          Nobody has yet checked this rule against the issuing authority's own published
          information, so treat every number here as an estimate. Confirm with
          <a href="#{e(resolved.authority_url)}" rel="nofollow noopener">the authority</a>
          before you rely on it, and
          <a href="#{e(source_file)}">correct this page</a> if you know better.
        </div>
      HTML
    end

    def answer_box
      cls = timeline.feasible? ? "answer" : "answer answer-warn"
      headline = if timeline.feasible?
                   "Start #{timeline.start_days_before_expiry} days before it expires"
                 else
                   "You cannot finish this before it expires"
                 end

      <<~HTML
        <section class="#{cls}">
          <h2>When to start</h2>
          <p class="headline">#{e(headline)}</p>
          <p>#{e(timeline.verdict)}</p>
        </section>
      HTML
    end

    def breakdown
      rows = [
        ["Processing, typical", "#{timeline.typical_days} days", "What most applicants experience."],
        ["Processing, worst case", "#{timeline.processing_days} days",
         "What the plan is built on. Planning against the median fails the people in the tail."]
      ]

      if (slowest = resolved.slowest_prerequisite)
        rows << ["Slowest prerequisite", "#{slowest["obtain_lead_days"]} days",
                 "#{slowest["item"]} — obtained before you can apply, so it sits in front of the process, not inside it."]
      end

      rows << ["Safety buffer", "#{timeline.buffer_days} days", "Margin for the steps nobody controls."]
      rows << ["<strong>Total lead time</strong>", "<strong>#{timeline.required_lead_days} days</strong>",
               "<strong>Sum of the above. This is the number that matters.</strong>"]

      body = rows.map do |label, value, note|
        "<tr><td>#{label}</td><td class=\"num\">#{value}</td><td class=\"note\">#{note}</td></tr>"
      end.join("\n")

      <<~HTML
        <section>
          <h2>How the date is calculated</h2>
          <div class="scroll">
          <table>
            <thead><tr><th>Component</th><th class="num">Days</th><th>Why</th></tr></thead>
            <tbody>
            #{body}
            </tbody>
          </table>
          </div>
        </section>
      HTML
    end

    def window_section
      opens = resolved.window_opens_days_before
      closes = resolved.window_closes_days_before
      grace = resolved.grace_days

      close_text = if closes.positive?
                     "Applications close #{closes} days before expiry."
                   elsif closes.zero?
                     "Applications close on the expiry date itself; there is no grace period afterwards."
                   else
                     "Late applications are still accepted for #{grace} days after expiry, though penalties may apply."
                   end

      open_text = opens >= 3650 ? "You may apply at any time." : "The earliest you may apply is #{opens} days before expiry."

      <<~HTML
        <section>
          <h2>The renewal window</h2>
          <p>#{e(open_text)} #{e(close_text)}</p>
          #{infeasibility_note}
        </section>
      HTML
    end

    def infeasibility_note
      return "" if timeline.feasible?

      advice = if timeline.covered_by_grace?
                 "Late renewal is permitted here, so the realistic goal is to minimise the gap " \
                   "and budget for the penalty rather than to finish on time."
               else
                 "There is no grace period, so expect a stretch with no valid document and plan around it."
               end

      <<~HTML
        <div class="banner banner-warn">
          <strong>The window is shorter than the process.</strong>
          Even starting on the first day you are legally allowed to apply, this takes about
          #{timeline.shortfall_days} days longer than the time remaining. That is a property of the
          process, not a mistake in your planning. #{advice}
        </div>
      HTML
    end

    def cost_section
      cost = resolved.cost
      return "" unless cost

      amount = cost["amount"].to_f
      main = if amount.positive?
               "<p class=\"headline\">#{e(format_money(amount, cost["currency"]))}</p>"
             else
               "<p>Not a flat fee.</p>"
             end

      expedited = if cost["expedited_amount"]
                    "<p>Fast-track: #{e(format_money(cost["expedited_amount"].to_f, cost["currency"]))}</p>"
                  else
                    ""
                  end

      note = cost["note"] ? "<p class=\"note\">#{e(cost["note"])}</p>" : ""

      "<section><h2>Cost</h2>#{main}#{expedited}#{note}</section>"
    end

    def format_money(amount, currency)
      whole = amount.round
      "#{currency} #{whole.to_s.reverse.scan(/\d{1,3}/).join(",").reverse}"
    end

    def documents_section
      items = resolved.required_documents.map do |doc|
        lead = doc["obtain_lead_days"].to_i
        tags = []
        tags << "<span class=\"tag\">allow #{lead} days to obtain</span>" if lead.positive?
        tags << "<span class=\"tag tag-soft\">only in some cases</span>" if doc["optional"]
        detail = doc["detail"] ? "<div class=\"note\">#{e(doc["detail"])}</div>" : ""
        "<li><strong>#{e(doc["item"])}</strong> #{tags.join(" ")}#{detail}</li>"
      end.join("\n")

      practical = []
      practical << "You must attend in person." if rule.data["in_person_required"]
      practical << "An appointment must be booked in advance." if resolved.appointment_required?
      practical_html = practical.empty? ? "" : "<p>#{e(practical.join(" "))}</p>"

      <<~HTML
        <section>
          <h2>What you need</h2>
          #{practical_html}
          <ul class="docs">#{items}</ul>
        </section>
      HTML
    end

    def consequence_section
      <<~HTML
        <section>
          <h2>If you miss it</h2>
          <p>#{e(rule.data["lapse_consequence"])}</p>
        </section>
      HTML
    end

    def notes_section
      notes = resolved.notes
      return "" if notes.empty?

      "<section><h2>Worth knowing</h2>#{notes.map { |n| "<p>#{e(n)}</p>" }.join}</section>"
    end

    def provenance
      verified = if resolved.draft?
                   "<strong>Unverified.</strong> No human has checked this against the authority yet."
                 else
                   "Last verified #{e(resolved.verified_on)} by #{e(resolved.verified_by)}."
                 end

      sources = resolved.source_urls.map do |url|
        "<li><a href=\"#{e(url)}\" rel=\"nofollow noopener\">#{e(url)}</a></li>"
      end.join

      <<~HTML
        <section class="provenance">
          <h2>Where this came from</h2>
          <p>#{verified}</p>
          <p>
            This is community-maintained reference information, not legal advice, and government
            processes change without notice. Always confirm against
            <a href="#{e(resolved.authority_url)}" rel="nofollow noopener">the issuing authority</a>
            before acting on it.
          </p>
          <ul>#{sources}</ul>
          <p><a href="#{e(source_file)}">View or correct the source data for this page</a>.</p>
        </section>
      HTML
    end
  end
end
