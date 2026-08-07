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
  elsif ENV["SECRET_KEY_BASE_DUMMY"]
    # Building an image, not running one. `assets:precompile` boots the whole
    # application in production mode to render the manifest, and it does that in
    # a Docker layer where no real key exists or should — baking one into an
    # image is how keys end up on a registry.
    #
    # Rails sets SECRET_KEY_BASE_DUMMY for exactly this case, so it is the
    # signal to trust: it means "nothing here will ever touch a database".
    # Placeholders rather than skipping the assignment, because Active Record
    # raises on a missing key at model load, and `Document` declares `encrypts`.
    config.active_record.encryption.primary_key = "asset_precompile_only_not_a_real_key"
    config.active_record.encryption.deterministic_key = "asset_precompile_only_not_a_real_key"
    config.active_record.encryption.key_derivation_salt = "asset_precompile_only_not_a_salt_xxx"
  else
    # Deliberately `fetch`. A production instance that boots without these would
    # accept a passport number and fail to encrypt it, which is worse than not
    # booting — and it would fail at the moment a user first typed one in,
    # rather than at deploy.
    config.active_record.encryption.primary_key =
      ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY")
    config.active_record.encryption.deterministic_key =
      ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY")
    config.active_record.encryption.key_derivation_salt =
      ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT")
  end
end
