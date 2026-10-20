# frozen_string_literal: true

module Jobs
  class ReliablePushTestNotification < ::Jobs::Base
    def execute(args)
      return unless SiteSetting.reliable_push_enabled && SiteSetting.reliable_push_test_notifications

      user = User.find_by(id: args[:user_id])
      return unless user && !user.do_not_disturb?

      return if SiteSetting.vapid_public_key.blank? || SiteSetting.vapid_private_key.blank?

      subscription = user.push_subscriptions.find_by(id: args[:subscription_id])
      return unless subscription

      data = subscription.parsed_data
      return if data["endpoint"].blank? || data.dig("keys", "auth").blank? ||
        data.dig("keys", "p256dh").blank?

      I18n.with_locale(user.effective_locale) do
        message = {
          title: I18n.t("discourse_reliable_push.test_title", site_title: SiteSetting.title),
          body: I18n.t("discourse_reliable_push.test_body"),
          icon: ActionController::Base.helpers.image_url("push-notifications/check.png"),
          badge: PushNotificationPusher.get_badge,
          base_url: Discourse.base_url,
          url: "/",
          tag: "#{Discourse.current_hostname}-reliable-push-test-#{SecureRandom.hex(6)}",
        }
        WebPush.payload_send(
          endpoint: data["endpoint"],
          message: message.to_json,
          p256dh: data.dig("keys", "p256dh"),
          auth: data.dig("keys", "auth"),
          vapid: {
            subject: Discourse.base_url,
            public_key: SiteSetting.vapid_public_key,
            private_key: SiteSetting.vapid_private_key,
            expiration: PushNotificationPusher::TOKEN_VALID_FOR_SECONDS,
          },
          open_timeout: PushNotificationPusher::CONNECTION_TIMEOUT_SECONDS,
          read_timeout: PushNotificationPusher::CONNECTION_TIMEOUT_SECONDS,
          ssl_timeout: PushNotificationPusher::CONNECTION_TIMEOUT_SECONDS,
        )
        # Provider acceptance is not proof of OS display or user receipt.
        Rails.logger.info(
          "[discourse-reliable-push] test push accepted by provider " \
            "user_id=#{user.id} subscription_id=#{subscription.id}",
        )
      end
    rescue WebPush::ExpiredSubscription
      subscription&.destroy!
    rescue WebPush::ResponseError, Timeout::Error, OpenSSL::SSL::SSLError => e
      # Do not log push endpoints, VAPID keys, or private notification payloads.
      Rails.logger.warn("[discourse-reliable-push] test push failed: #{e.class}")
    end
  end
end
