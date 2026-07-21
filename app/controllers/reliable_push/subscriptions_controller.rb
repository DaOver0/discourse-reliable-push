# frozen_string_literal: true

module ::ReliablePush
  class SubscriptionsController < ::ApplicationController
    requires_login

    def sync
      subscription = params[:subscription]

      if subscription.blank?
        # This browser has no PushManager subscription. Do not disable the
        # user's other devices: there is no endpoint here that identifies the
        # device being removed. Stale mirrored endpoints are disabled by
        # 404/410 handling or disappear when their core subscription is pruned.
        render json: success_json.merge(enabled: false)
        return
      end

      record =
        Subscription.sync!(
          user: current_user,
          subscription: subscription,
          user_agent: request.user_agent,
        )

      # A delivery may have arrived before this browser opened. Re-prepare the
      # recent no-subscription rows after a successful sync.
      Delivery
        .where(user_id: current_user.id, state: %i[no_subscription failed])
        .where("expires_at > ?", Time.zone.now)
        .find_each do |delivery|
          delivery.update_columns(
            state: Delivery.states[:pending],
            last_error: nil,
            updated_at: Time.zone.now,
          )
          Jobs.enqueue(:reliable_push_prepare_delivery, delivery_id: delivery.id)
        end

      render json: success_json.merge(subscription_id: record.id, enabled: true)
    rescue ArgumentError => e
      render_json_error(e.message, status: 422)
    end
  end
end
