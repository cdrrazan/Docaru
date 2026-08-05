class CreateReminders < ActiveRecord::Migration[8.1]
  def change
    create_table :reminders do |t|
      t.references :document, null: false, foreign_key: true

      # A reminder row records something already sent; it is not a queue of
      # things to send. The schedule is recomputed from the rule every night, so
      # correcting an expiry date reshapes every future reminder for free —
      # whereas a materialised queue would quietly keep firing the old dates.
      t.string :kind, null: false
      t.date :scheduled_for, null: false
      t.datetime :sent_at

      t.timestamps
    end

    # The dedupe key. Sending the same stage twice is worse than not sending it
    # at all: people stop reading a channel that repeats itself, and this
    # channel is the entire retention mechanism.
    add_index :reminders, [ :document_id, :kind ], unique: true
  end
end
