# frozen_string_literal: true

# Stores the two wrapped copies of a household's vault key.
#
# There is deliberately no code here that unwraps, inspects or validates the
# contents of either blob, for the same reason `AttachmentsController` never
# decrypts: the keys that would open them are derived in the browser from a
# passphrase and a recovery code the server never receives. What arrives is
# opaque base64, and what leaves is the same base64.
#
# The honest limit of this design: somebody who already has a session can
# overwrite the wrapping and lock the household out. They cannot read anything —
# the vault key stays sealed inside blobs they cannot open — so the exposure is
# denial of access, not disclosure, and it requires a compromise that already
# lets them delete every document by hand. Fixing it would need the server to
# verify knowledge of the passphrase, which is precisely what it must not know.
class VaultKeysController < ApplicationController
  def create
    if household.vault_initialised?
      return render json: { errors: [ "This household already has a vault key." ] },
                    status: :conflict
    end

    household.store_vault_key!(**wrapping)

    render json: { status: "created" }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
  end

  # Recovery and passphrase change are the same operation seen from two sides:
  # the browser has proved it holds the vault key by producing a new wrapping of
  # it, and the server has no way to check that claim and no need to. A caller
  # who did not hold the key can only replace it with a key that opens nothing,
  # which is the lockout case above rather than a new one.
  def update
    unless household.vault_initialised?
      return render json: { errors: [ "This household has no vault key to replace." ] },
                    status: :not_found
    end

    household.rewrap_vault_key!(**wrapping)

    render json: { status: "rewrapped" }
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
  end

  private

  def wrapping
    permitted = params.expect(vault_key: [ :wrapped, :wrapped_iv, :recovery_wrapped, :recovery_wrapped_iv ])

    {
      wrapped: permitted[:wrapped],
      wrapped_iv: permitted[:wrapped_iv],
      recovery_wrapped: permitted[:recovery_wrapped],
      recovery_wrapped_iv: permitted[:recovery_wrapped_iv]
    }
  end
end
