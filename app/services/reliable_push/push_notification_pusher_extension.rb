# frozen_string_literal: true

module ReliablePush
  module PushNotificationPusherExtension
    def push(user, payload)
      if SiteSetting.reliable_push_enabled && SiteSetting.reliable_push_replace_core_web_push
        ingestion = ReliablePush::EventIngestor.from_core_push(user:, payload:)
        return super if ingestion.nil?
        return ReliablePush::PayloadBuilder.from_core_payload(user:, payload:)
      end

      super
    end
  end
end
