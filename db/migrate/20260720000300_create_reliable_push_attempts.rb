# frozen_string_literal: true

class CreateReliablePushAttempts < ActiveRecord::Migration[7.0]
  def change
    create_table :reliable_push_attempts do |t|
      t.bigint :delivery_id, null: false
      t.bigint :subscription_id, null: false
      t.integer :state, null: false, default: 0
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.integer :last_response_code
      t.text :last_error
      t.timestamps
    end

    add_index :reliable_push_attempts, %i[delivery_id subscription_id], unique: true, name: "idx_reliable_push_attempts_delivery_subscription"
    add_index :reliable_push_attempts, %i[state next_attempt_at]
  end
end
