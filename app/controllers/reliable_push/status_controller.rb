# frozen_string_literal: true

module ::ReliablePush
  class StatusController < ::ApplicationController
    requires_login

    def show
      Subscription.mirror_core_for_user!(current_user)

      render json: {
        enabled: SiteSetting.reliable_push_enabled,
        replace_core_web_push: SiteSetting.reliable_push_replace_core_web_push,
        active_subscriptions:
          Subscription.active.where(user_id: current_user.id).count,
        deliveries:
          Delivery
            .where(user_id: current_user.id)
            .group(:state)
            .count
            .transform_keys { |state| Delivery.states.key(state) || state },
        preferences: PreferenceResolver.as_json(current_user),
      }
    end
  end
end
