# frozen_string_literal: true

module ::ReliablePush
  module Admin
    class StatusController < ::Admin::AdminController
      def show
        render json: {
          enabled: SiteSetting.reliable_push_enabled,
          replace_core_web_push: SiteSetting.reliable_push_replace_core_web_push,
          subscriptions: Subscription.group(:enabled).count,
          deliveries: Delivery.group(:state).count.transform_keys { |state| Delivery.states.key(state) || state },
          attempts: Attempt.group(:state).count.transform_keys { |state| Attempt.states.key(state) || state },
          oldest_pending_delivery:
            Delivery.where(state: %i[pending preparing]).minimum(:created_at),
          latest_delivery: Delivery.maximum(:created_at),
        }
      end
    end
  end
end
