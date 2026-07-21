# frozen_string_literal: true

module ::ReliablePush
  module PushNotificationPusherExtension
    def push(user, payload)
      return super unless SiteSetting.reliable_push_enabled
      return super unless SiteSetting.reliable_push_replace_core_web_push

      result = ::ReliablePush::EventIngestor.from_core_push(user: user, payload: payload)

      case result.status
      when :handled, :suppressed
        # Preserve the return contract without invoking the original sender.
        ::ReliablePush::PayloadBuilder.from_core_payload(user: user, payload: payload)
      else
        # A plugin failure must never silently discard a notification.
        super
      end
    rescue StandardError => e
      Discourse.warn_exception(
        e,
        message: "Reliable Push interception failed; falling back to core Web Push",
        env: { user_id: user&.id },
      )
      super
    end
  end
end
