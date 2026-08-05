class CreateAttachments < ActiveRecord::Migration[8.1]
  def change
    create_table :attachments do |t|
      t.references :document, null: false, foreign_key: true

      # The initialisation vector for AES-GCM. Public by design: it must never
      # repeat for a given key, but it is not secret, and the browser needs it
      # back in order to decrypt.
      t.string :iv, null: false

      # Describes the plaintext so the browser knows what it decrypted into.
      # Deliberately coarse, and no filename is kept — "asylum-appeal-refusal.jpg"
      # would tell the server exactly the sort of thing the encryption exists to
      # stop it learning.
      t.string :content_type, null: false
      t.integer :byte_size, null: false
      t.integer :page_no, null: false, default: 1

      t.timestamps
    end

    add_index :attachments, [ :document_id, :page_no ]
  end
end
