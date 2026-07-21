# frozen_string_literal: true

module ::ReliablePush
  class Attempt < ActiveRecord::Base
    self.table_name = "reliable_push_attempts"

    belongs_to :delivery,
               class_name: "ReliablePush::Delivery",
               inverse_of: :attempts
    belongs_to :subscription,
               class_name: "ReliablePush::Subscription",
               inverse_of: :attempts

    enum :state,
         {
           pending: 0,
           sending: 1,
           accepted: 2,
           retrying: 3,
           expired: 4,
           failed: 5,
           cancelled: 6,
         }

    validates :delivery_id, uniqueness: { scope: :subscription_id }

    def terminal?
      accepted? || failed? || expired? || cancelled?
    end
  end
end
