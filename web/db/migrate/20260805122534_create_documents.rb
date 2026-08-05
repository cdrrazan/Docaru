class CreateDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.references :member, null: false, foreign_key: true

      # Metadata stays plaintext on purpose. The server has to compute
      # reminders and render a dashboard, and it cannot do either over
      # ciphertext. What it must never hold in the clear is the document
      # itself — that is the attachment, encrypted in the browser.
      t.string :kind, null: false
      t.string :issuing_country, null: false
      t.string :applying_from
      t.date :expires_on, null: false
      t.date :issued_on
      t.string :label

      # Encrypted at rest via ActiveRecord::Encryption. A passport number is
      # not needed to compute a date, so the server has no reason to be able
      # to read it. Text rather than string: ciphertext is a JSON envelope and
      # runs considerably longer than the value it wraps.
      t.text :identifier
      t.text :notes

      t.timestamps
    end

    # The scheduler sweeps by date across every household, so this is the one
    # index that decides whether the nightly job stays cheap.
    add_index :documents, :expires_on
  end
end
