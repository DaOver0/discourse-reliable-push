# frozen_string_literal: true

module Jobs
  class ReliablePushCleanup < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      cutoff = SiteSetting.reliable_push_cleanup_after_days.days.ago

      ::ReliablePush::Delivery
        .where("created_at < ?", cutoff)
        .where(state: %i[opened cancelled failed expired no_subscription])
        .in_batches(of: 1000)
        .delete_all

      ::ReliablePush::Subscription
        .where(enabled: false)
        .where("updated_at < ?", cutoff)
        .in_batches(of: 1000)
        .delete_all
    end
  end
end
