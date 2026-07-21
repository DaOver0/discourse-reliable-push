# frozen_string_literal: true

module ReliablePush
  class Sender
    TOKEN_VALID_FOR_SECONDS = 5.minutes.to_i

    def self.call(subscription:, message:)
      WebPush.payload_send(
        endpoint: subscription.endpoint,
        message: message.to_json,
        p256dh: subscription.p256dh,
        auth: subscription.auth,
        vapid: {
          subject: Discourse.base_url,
          public_key: SiteSetting.vapid_public_key,
          private_key: SiteSetting.vapid_private_key,
          expiration: TOKEN_VALID_FOR_SECONDS,
        },
        open_timeout: SiteSetting.reliable_push_open_timeout_seconds,
        read_timeout: SiteSetting.reliable_push_read_timeout_seconds,
        ssl_timeout: SiteSetting.reliable_push_open_timeout_seconds,
      )
    end
  end
end
