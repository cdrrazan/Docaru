# A household you can actually look at.
#
# An empty vault demonstrates nothing. This builds one holding what a real
# household keeps: mostly documents that never expire and simply need to be
# reachable — a citizenship certificate, a degree, a land deed — plus the
# handful that do expire, in every state the application can be in, and the
# prerequisite chain that is the thing no competitor does.
#
# The proportions are the point. Six of these thirteen have no deadline at all,
# which is roughly what a drawer looks like.
#
# Dates are relative to today, so the demo is never stale and never has to be
# regenerated.
#
#   bin/rails db:seed          # idempotent; safe to run repeatedly
#
# Never runs outside development and test. `db:prepare` runs seeds when it
# creates a database, and the Docker entrypoint runs `db:prepare` — so an
# unguarded seed would plant a known password on every new self-hosted instance
# the moment it booted.
unless Rails.env.local?
  Rails.logger.info "Seeds skipped: demo data is for development and test only."
  return
end

PASSWORD = "demo-password-change-me"

household = Household.find_or_create_by!(name: "The Bhattarai household") do |h|
  # The household plan, so member and document limits stay out of the way of
  # what is being demonstrated. The pricing page still shows the free tier.
  h.plan = "household"
end

user = User.find_or_initialize_by(email_address: "demo@renewaru.test")
user.update!(name: "Sunita", household: household, password: PASSWORD, password_confirmation: PASSWORD)

people = {
  self: household.members.find_or_create_by!(name: "Sunita") { |m| m.relationship = "Me" },
  mother: household.members.find_or_create_by!(name: "Aama") { |m| m.relationship = "Mother" },
  brother: household.members.find_or_create_by!(name: "Bikash") { |m| m.relationship = "Brother" }
}

# expires_on is expressed as days from today and chosen against each rule's real
# lead time, so every row lands in the state the comment claims. The arithmetic
# is in the comments rather than hard-coded dates for the same reason.
documents = [
  # Passport from the UK needs 181 days of lead time. Expiring in 243 leaves
  # about two months before the start date: on track, nothing to do yet.
  { member: :self, kind: "passport", issuing_country: "NP", applying_from: "GB",
    expires_on: 243, label: nil, note: "on track" },

  # Same rule, expiring in 195 days, so the start date is a fortnight away.
  { member: :mother, kind: "passport", issuing_country: "NP", applying_from: "GB",
    expires_on: 195, label: nil, note: "start now" },

  # Police clearance from the UK needs 132 days. Expiring in 100 means the day
  # to start was a month ago — the failure this product exists to prevent.
  { member: :self, kind: "police_clearance", issuing_country: "NP", applying_from: "GB",
    expires_on: 100, label: nil, note: "overdue" },

  # A Nepali driving licence cannot be renewed inside its own window from
  # anywhere: the process takes longer than the window is open. Reported rather
  # than hidden, because it is true.
  { member: :brother, kind: "drivers_licence", issuing_country: "NP", applying_from: "domestic",
    expires_on: 120, label: nil, note: "impossible" },

  # Expired a fortnight ago, and it is also the prerequisite below.
  { member: :brother, kind: "insurance_policy", issuing_country: "NP", applying_from: "domestic",
    expires_on: -14, label: "Third-party motor insurance", note: "expired" },

  # The pair that makes the point. Nepal will not renew a vehicle registration
  # without current insurance, and the insurance above has already lapsed — so
  # this renewal is blocked before it starts, which neither date shows alone.
  { member: :brother, kind: "vehicle_registration", issuing_country: "NP", applying_from: "domestic",
    expires_on: 60, label: "Bluebook — Bagmati 2 Pa 3344", note: "blocked by the insurance above" },

  # No rule in the dataset for this one. The dashboard says so rather than
  # inventing a date, and reminders fall back to the expiry date.
  { member: :mother, kind: "residence_permit", issuing_country: "GB", applying_from: "domestic",
    expires_on: 210, label: "UK biometric residence permit", note: "no rule yet" },

  # ---- and the larger half of a real vault -------------------------------
  #
  # None of these expire, none of them generate a reminder, and every one of
  # them is a thing somebody actually needs at short notice from the wrong city.
  # A vault that could only hold the documents with deadlines would be missing
  # most of what a household keeps.
  { member: :self, kind: "citizenship_certificate", issuing_country: "NP", applying_from: nil,
    expires_on: nil, label: nil, note: "stored" },
  { member: :self, kind: "degree_certificate", issuing_country: "NP", applying_from: nil,
    expires_on: nil, label: "BSc Computer Science, Tribhuvan University", note: "stored" },
  { member: :self, kind: "academic_transcript", issuing_country: "NP", applying_from: nil,
    expires_on: nil, label: "Undergraduate transcript", note: "stored" },
  { member: :mother, kind: "birth_certificate", issuing_country: "NP", applying_from: nil,
    expires_on: nil, label: nil, note: "stored" },
  { member: :brother, kind: "property_deed", issuing_country: "NP", applying_from: nil,
    expires_on: nil, label: "Lalitpur land certificate (lalpurja)", note: "stored" },
  { member: :mother, kind: "marriage_certificate", issuing_country: "NP", applying_from: nil,
    expires_on: nil, label: nil, note: "stored" }
]

documents.each do |attributes|
  member = people.fetch(attributes[:member])

  document = member.documents.find_or_initialize_by(
    kind: attributes[:kind], issuing_country: attributes[:issuing_country]
  )
  document.update!(
    applying_from: attributes[:applying_from],
    # nil stays nil: a document with no expiry is the normal case here, not a
    # missing value to be defaulted.
    expires_on: attributes[:expires_on] && Date.current + attributes[:expires_on],
    label: attributes[:label]
  )
end

Rails.logger.info "Seeded #{household.members.count} people and #{household.documents.count} documents."

# Printed rather than logged: somebody running this wants the credentials, and
# hunting for them in log/development.log is a poor first five minutes.
if Rails.env.development?
  puts <<~DEMO

    Demo household ready.

      Sign in at  /session/new
      Email       demo@renewaru.test
      Password    #{PASSWORD}

    #{household.documents.count} documents across #{household.members.count} people.
    #{household.documents.count { |d| !d.dated? }} of them never expire — a citizenship certificate,
    a degree, a land deed — which is roughly what a real drawer looks like, and
    the reason the vault exists at all.

    The #{household.documents.count(&:dated?)} that do expire cover every state the dashboard can
    show, including a vehicle registration blocked by insurance that has already
    lapsed.
  DEMO
end
