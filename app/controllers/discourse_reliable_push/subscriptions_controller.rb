# frozen_string_literal: true

module DiscourseReliablePush
  class SubscriptionsController < ::ApplicationController
    requires_plugin DiscourseReliablePush::PLUGIN_NAME
    before_action :ensure_logged_in
    before_action :ensure_plugin_enabled

    # Read-only account ownership check. The push endpoint/keys are never echoed back.
    def status
      render json: { registered: own_subscription.present? }
    end

    # Idempotent registration. Re-uses core's subscription method and storage, so
    # Forum/Chat push still follows native notification policies, DND and time windows.
    def sync
      push_params = validated_subscription_params
      serialized = push_params.to_json

      # One Service Worker subscription corresponds to one browser profile, not to
      # multiple simultaneously logged-in accounts. Avoid leaking a former account's
      # private notifications after switching accounts in the same installed PWA.
      PushSubscription.transaction do
        PushSubscription.where(data: serialized).where.not(user_id: current_user.id).delete_all
        PushNotificationPusher.subscribe(current_user, push_params, "false")
      end

      render json: { registered: current_user.push_subscriptions.exists?(data: serialized) }
    end

    # Sends exactly one test push to the subscription supplied by this browser;
    # enqueue result is NOT a guarantee of acceptance or display on the device.
    def test
      raise Discourse::InvalidAccess unless SiteSetting.reliable_push_test_notifications

      subscription = own_subscription
      raise Discourse::NotFound unless subscription

      RateLimiter.new(current_user, "reliable-push-test", 1.minute, 2).performed!
      Jobs.enqueue(
        :reliable_push_test_notification,
        user_id: current_user.id,
        subscription_id: subscription.id,
      )
      render json: { queued: true }
    end

    private

    def ensure_plugin_enabled
      raise Discourse::NotFound unless SiteSetting.reliable_push_enabled
    end

    def own_subscription
      current_user.push_subscriptions.find_by(data: validated_subscription_params.to_json)
    end

    def validated_subscription_params
      result = params.require(:subscription).permit(:endpoint, keys: %i[p256dh auth])
      endpoint = result[:endpoint].to_s
      p256dh = result.dig(:keys, :p256dh).to_s
      auth = result.dig(:keys, :auth).to_s
      valid_endpoint = endpoint.bytesize.between?(20, 2048) &&
        endpoint.start_with?("https://") &&
        URI.parse(endpoint).host.present?
      valid_keys = p256dh.bytesize.between?(40, 256) && auth.bytesize.between?(8, 128) &&
        p256dh.match?(/\A[A-Za-z0-9_-]+\z/) && auth.match?(/\A[A-Za-z0-9_-]+\z/)
      raise Discourse::InvalidParameters.new(:subscription) unless valid_endpoint && valid_keys

      result
    rescue URI::InvalidURIError
      raise Discourse::InvalidParameters.new(:subscription)
    end
  end
end
