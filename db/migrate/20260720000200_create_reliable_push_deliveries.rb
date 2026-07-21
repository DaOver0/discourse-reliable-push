# frozen_string_literal: true

class CreateReliablePushDeliveries < ActiveRecord::Migration[7.0]
  def change
    create_table :reliable_push_deliveries do |t|
      t.integer :user_id, null: false
      t.string :kind, null: false, limit: 80
      t.string :source_type, limit: 120
      t.bigint :source_id
      t.string :dedupe_key, null: false, limit: 255
      t.jsonb :payload, null: false, default: {}
      t.integer :priority, null: false, default: 0
      t.integer :state, null: false, default: 0
      t.string :ack_token, null: false, limit: 64
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :received_at
      t.datetime :opened_at
      t.text :last_error
      t.timestamps
    end

    add_index :reliable_push_deliveries, %i[user_id dedupe_key], unique: true, name: "idx_reliable_push_deliveries_dedupe"
    add_index :reliable_push_deliveries, :ack_token, unique: true
    add_index :reliable_push_deliveries, %i[state expires_at]
    add_index :reliable_push_deliveries, %i[source_type source_id]
  end
end
