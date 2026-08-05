class CreatePushSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :push_subscriptions do |t|
      # index: false because the composite below already leads with user_id.
      t.references :user, null: false, foreign_key: true, index: false

      # Where this browser's push service will accept a message, and the keys it
      # must be encrypted to. The endpoint is the identity: one row per browser
      # per device, so the same person signing in on a phone and a laptop gets
      # two and both are reminded.
      t.string :endpoint, null: false, limit: 512
      t.string :p256dh_key, null: false
      t.string :auth_key, null: false

      # "Which of my devices is this?" is unanswerable from an endpoint URL, and
      # revoking one you no longer own is the whole reason to show a list.
      t.string :user_agent

      # Set when the push service reports the subscription gone. Kept rather
      # than deleted on the spot so the sweep can say how many devices it could
      # not reach, instead of silently shrinking.
      t.datetime :expired_at

      t.timestamps
    end

    # MySQL will not put 512 utf8mb4 characters in a unique key, so this indexes
    # a prefix long enough to be selective. Endpoints differ well inside 191
    # characters — the host and the leading path are what vary.
    add_index :push_subscriptions, [ :user_id, :endpoint ],
              length: { endpoint: 191 }, unique: true
  end
end
