# frozen_string_literal: true

class AddReliablePushSupportingIndexes < ActiveRecord::Migration[7.0]
  SUBSCRIPTION_INDEX = "idx_reliable_push_subscriptions_user_enabled"
  DELIVERY_INDEX = "idx_reliable_push_deliveries_user_created"

  def up
    unless index_exists?(
             :reliable_push_subscriptions,
             %i[user_id enabled],
             name: SUBSCRIPTION_INDEX,
           )
      add_index :reliable_push_subscriptions,
                %i[user_id enabled],
                name: SUBSCRIPTION_INDEX
    end

    unless index_exists?(
             :reliable_push_deliveries,
             %i[user_id created_at],
             name: DELIVERY_INDEX,
           )
      add_index :reliable_push_deliveries,
                %i[user_id created_at],
                name: DELIVERY_INDEX
    end
  end

  def down
    remove_index :reliable_push_subscriptions, name: SUBSCRIPTION_INDEX if
      index_exists?(:reliable_push_subscriptions, name: SUBSCRIPTION_INDEX)
    remove_index :reliable_push_deliveries, name: DELIVERY_INDEX if
      index_exists?(:reliable_push_deliveries, name: DELIVERY_INDEX)
  end
end
