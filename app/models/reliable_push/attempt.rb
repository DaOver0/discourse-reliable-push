# frozen_string_literal: true

module ReliablePush
  class Attempt < ActiveRecord::Base
    self.table_name = "reliable_push_attempts"

    belongs_to :delivery, class_name: "ReliablePush::Delivery"
    belongs_to :subscription, class_name: "ReliablePush::Subscription"

    enum :state, { pending: 0, sending: 1, accepted: 2, retrying: 3, expired: 4, failed: 5, cancelled: 6 }

    validates :subscription_id, uniqueness: { scope: :delivery_id }

    def terminal?
      accepted? || expired? || failed? || cancelled?
    end
  end
end
