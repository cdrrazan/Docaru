class AddVaultSaltToHouseholds < ActiveRecord::Migration[8.1]
  def change
    # Per-household PBKDF2 salt. Not a secret — its job is to make a precomputed
    # attack against one household useless against every other. It lives
    # server-side so any device in the household can derive the same key from
    # the same passphrase without the passphrase ever being transmitted.
    add_column :households, :vault_salt, :string
  end
end
