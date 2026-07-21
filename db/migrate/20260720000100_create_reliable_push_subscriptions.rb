# frozen_string_literal: true

class CreateReliablePushSubscriptions < ActiveRecord::Migration[7.0]
  def change
    create_table :reliable_push_subscriptions do |t|
      t.integer :user_id, null: false
      t.string :endpoint_digest, null: false, limit: 64
      t.text :endpoint, null: false
      t.text :p256dh, null: false
      t.text :auth, null: false
      t.string :user_agent, limit: 1000
      t.boolean :enabled, null: false, default: true
      t.integer :failure_count, null: false, default: 0
      t.datetime :last_success_at
      t.datetime :last_failure_at
      t.timestamps
    end

    add_index :reliable_push_subscriptions, :user_id
    add_index :reliable_push_subscriptions, :endpoint_digest, unique: true
  end
end
