# frozen_string_literal: true

class CreateReliablePushPreferences < ActiveRecord::Migration[7.0]
  def change
    create_table :reliable_push_preferences do |t|
      t.integer :user_id, null: false
      t.boolean :topic_posts, null: false, default: true
      t.boolean :new_topics, null: false, default: true
      t.boolean :chat_messages, null: false, default: true
      t.boolean :mentions_replies, null: false, default: true
      t.boolean :private_messages, null: false, default: true
      t.boolean :badges, null: false, default: true
      t.boolean :account_events, null: false, default: true
      t.boolean :new_categories, null: false, default: true
      t.boolean :resenha, null: false, default: true
      t.boolean :other, null: false, default: true
      t.boolean :sound, null: false, default: true
      t.boolean :tab_blink, null: false, default: true
      t.timestamps
    end

    add_index :reliable_push_preferences, :user_id, unique: true
  end
end
