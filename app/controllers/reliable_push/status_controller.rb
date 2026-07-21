# frozen_string_literal: true

module ReliablePush
  class StatusController < ::ApplicationController
    requires_plugin ReliablePush::PLUGIN_NAME
    before_action :ensure_logged_in

    def show
      subscriptions = Subscription.where(user_id: current_user.id)
      render json: {
        enabled: SiteSetting.reliable_push_enabled,
        active_subscriptions: subscriptions.active.count,
        subscriptions: subscriptions.count,
        recent_deliveries: Delivery.where(user_id: current_user.id).where("created_at > ?", 7.days.ago).group(:state).count,
      }
    end
  end
end
