# frozen_string_literal: true

module ReliablePush
  class SubscriptionsController < ::ApplicationController
    requires_plugin ReliablePush::PLUGIN_NAME
    before_action :ensure_logged_in

    def sync
      subscription = params[:subscription]
      subscription = subscription.to_unsafe_h if subscription.respond_to?(:to_unsafe_h)
      Subscription.sync!(user: current_user, subscription: subscription, user_agent: request.user_agent)
      render json: success_json
    rescue ArgumentError => e
      render json: failed_json.merge(error: e.message), status: :unprocessable_entity
    end
  end
end
