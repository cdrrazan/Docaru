# frozen_string_literal: true

# Envelope encryption for the vault.
#
# Until now the passphrase-derived key *was* the key the scans were encrypted
# with, which made two things impossible: changing a passphrase without
# re-encrypting every file, and surviving a forgotten one at all. Now a random
# vault key encrypts the files, and this table holds that key twice over —
# wrapped under the passphrase, and wrapped under a recovery code.
#
# None of these columns is a secret the server can use. Each is ciphertext whose
# key is derived in the browser from something the server never receives, so an
# operator, a stolen backup and a subpoena all get the same thing: two blobs and
# no way in.
class AddVaultKeyToHouseholds < ActiveRecord::Migration[8.1]
  def change
    change_table :households, bulk: true do |t|
      # The vault key, encrypted under PBKDF2(passphrase, vault_salt).
      t.text :wrapped_key
      t.string :wrapped_key_iv

      # The same vault key, encrypted under PBKDF2(recovery_code,
      # recovery_salt). A separate salt so the two derivations cannot be
      # compared, and a separate column so losing one leaves the other.
      t.text :recovery_wrapped_key
      t.string :recovery_wrapped_key_iv
      t.string :recovery_salt

      # When the recovery code was last used or replaced. Shown to the user,
      # because a recovery code that was used and not regenerated is a spent
      # one, and they should be told rather than left to find out.
      t.datetime :recovery_used_at
    end
  end
end
