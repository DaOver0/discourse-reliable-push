# frozen_string_literal: true

module Jobs
  class ReliablePushCleanup < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      cutoff = SiteSetting.reliable_push_retention_days.days.ago
      terminal_states = ::ReliablePush::Delivery.states.values_at(:opened, :no_subscription, :expired, :failed, :cancelled)
      ::ReliablePush::Delivery.where(state: terminal_states).where("updated_at < ?", cutoff).find_in_batches do |records|
        delivery_ids = records.map(&:id)
        ::ReliablePush::Attempt.where(delivery_id: delivery_ids).delete_all
        ::ReliablePush::Delivery.where(id: delivery_ids).delete_all
      end
      ::ReliablePush::Subscription.where(enabled: false).where("updated_at < ?", cutoff).delete_all
    end
  end
end
