# frozen_string_literal: true

module ReliablePush
  module Admin
    class StatusController < ::ApplicationController
      requires_plugin ReliablePush::PLUGIN_NAME
      before_action :ensure_admin

      def show
        since = 7.days.ago
        recent_deliveries = Delivery.where("created_at > ?", since)
        recent_attempts = Attempt.where("created_at > ?", since)

        render json: {
          enabled: SiteSetting.reliable_push_enabled,
          replace_core_web_push: SiteSetting.reliable_push_replace_core_web_push,
          subscriptions: {
            total: Subscription.count,
            active: Subscription.active.count,
            users: Subscription.active.distinct.count(:user_id),
          },
          deliveries_last_7_days: recent_deliveries.group(:state).count,
          attempts_last_7_days: recent_attempts.group(:state).count,
          recent_failures: recent_attempts
            .where(state: Attempt.states.values_at(:failed, :expired))
            .order(updated_at: :desc)
            .limit(50)
            .pluck(:id, :delivery_id, :subscription_id, :last_response_code, :last_error, :updated_at)
            .map do |id, delivery_id, subscription_id, code, error, updated_at|
              {
                id: id,
                delivery_id: delivery_id,
                subscription_id: subscription_id,
                response_code: code,
                error: error,
                updated_at: updated_at,
              }
            end,
        }
      end
    end
  end
end
