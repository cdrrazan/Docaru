class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions do |t|
      # One at a time. A household that resubscribes reuses this row rather than
      # accumulating a history nobody reads and every query has to filter.
      t.references :household, null: false, foreign_key: true, index: { unique: true }

      t.string :paddle_subscription_id, null: false
      t.string :paddle_customer_id
      t.string :price_id

      # Paddle's own vocabulary, stored verbatim. Translating it at the boundary
      # would mean a status we had never seen before becoming one we silently
      # mapped to something else — and the wrong guess here is the one that
      # stops somebody's reminders.
      t.string :status, null: false

      t.date :renews_on
      t.datetime :canceled_at

      # Out-of-order webhooks are normal rather than exceptional. This is what
      # lets a stale event be recognised and dropped instead of reverting a
      # newer one.
      t.datetime :last_event_at

      t.timestamps
    end

    add_index :subscriptions, :paddle_subscription_id, unique: true

    # Idempotency. Paddle retries until it gets a 2xx, so the same event
    # arriving twice is the normal case, not a fault.
    create_table :webhook_events do |t|
      t.string :provider, null: false
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.datetime :occurred_at

      t.timestamps
    end

    add_index :webhook_events, [ :provider, :event_id ], unique: true
  end
end
