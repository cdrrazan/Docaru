# frozen_string_literal: true

# Keys for the encrypted columns (document identifier and notes).
#
# Read from the environment rather than from Rails credentials so that somebody
# self-hosting can supply their own keys without re-encrypting the repository's
# credentials file — which they cannot decrypt anyway, and should not have to.
#
# Development and test use fixed, obviously-fake keys. They are checked in
# deliberately: they protect nothing, they are never used in production, and
# pretending otherwise by generating them would only make it harder to run the
# test suite on a fresh checkout.
Rails.application.configure do
  if Rails.env.local?
    config.active_record.encryption.primary_key = "development_only_primary_key_do_not_use"
    config.active_record.encryption.deterministic_key = "development_only_deterministic_key_xx"
    config.active_record.encryption.key_derivation_salt = "development_only_derivation_salt_xxxx"
  else
    config.active_record.encryption.primary_key =
      ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY")
    config.active_record.encryption.deterministic_key =
      ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY")
    config.active_record.encryption.key_derivation_salt =
      ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT")
  end
end
