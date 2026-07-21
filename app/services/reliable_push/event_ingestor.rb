# frozen_string_literal: true

module ReliablePush
  class EventIngestor
    POST_TYPES = %i[mentioned group_mentioned replied quoted private_message invited_to_private_message watching_first_post watching_category_or_tag posted].freeze
    CHAT_TYPES = %i[chat_mention chat_message chat_invitation chat_quoted chat_watched_thread].freeze

    PRIORITIES = {
      "chat_mention" => 100,
      "mentioned" => 100,
      "group_mentioned" => 95,
      "private_message" => 90,
      "replied" => 80,
      "quoted" => 75,
      "chat_message" => 70,
      "watching_first_post" => 55,
      "watching_category_or_tag" => 45,
      "posted" => 40,
      "granted_badge" => 35,
    }.freeze

    class << self
      def from_core_push(user:, payload:)
        return :skipped unless eligible_user?(user)

        payload = payload.to_h.with_indifferent_access
        type = type_name(payload[:notification_type])
        return :skipped unless enabled_type?(type)

        message = PayloadBuilder.from_core_payload(user:, payload:)
        ingest(
          user: user,
          kind: type,
          dedupe_key: dedupe_key(type:, payload:),
          payload: message,
          priority: PRIORITIES.fetch(type, 10),
          source_type: source_type(payload),
          source_id: source_id(payload),
        )
      rescue StandardError => e
        Discourse.warn_exception(e, message: "Reliable Push failed to ingest core push", env: { user_id: user&.id })
      end

      def from_notification(notification)
        user = notification.user
        return unless eligible_user?(user)

        type = type_name(notification.notification_type)
        return unless enabled_type?(type)

        payload = PayloadBuilder.from_notification(notification)
        semantic_payload = payload.merge(
          post_id: payload["post_id"],
          chat_message_id: payload["chat_message_id"],
          topic_id: notification.topic_id,
          notification_id: notification.id,
        ).with_indifferent_access

        ingest(
          user: user,
          kind: type,
          dedupe_key: dedupe_key(type:, payload: semantic_payload),
          payload: payload,
          priority: PRIORITIES.fetch(type, 10),
          source_type: "Notification",
          source_id: notification.id,
        )
      rescue StandardError => e
        Discourse.warn_exception(e, message: "Reliable Push failed to ingest notification", env: { notification_id: notification&.id })
      end

      def broadcast_new_topic(user:, post:)
        return unless eligible_user?(user)
        return if AccessChecker.topic_muted?(user:, topic_id: post.topic_id)
        payload = PayloadBuilder.for_new_topic_broadcast(user:, post:)
        ingest(
          user: user,
          kind: "broadcast_new_topic",
          dedupe_key: post_dedupe_key(post.id),
          payload: payload,
          priority: 30,
          source_type: "Post",
          source_id: post.id,
        )
      end

      def broadcast_topic_post(user:, post:)
        return unless SiteSetting.reliable_push_post_notifications
        return unless eligible_user?(user)
        return if user.id == post.user_id
        return unless Guardian.new(user).can_see?(post.topic)
        return if AccessChecker.topic_muted?(user:, topic_id: post.topic_id)

        payload = PayloadBuilder.for_topic_post_broadcast(user:, post:)
        ingest(
          user: user,
          kind: post.post_number == 1 ? "broadcast_new_topic" : "broadcast_topic_post",
          dedupe_key: post_dedupe_key(post.id),
          payload: payload,
          priority: post.post_number == 1 ? 30 : 25,
          source_type: "Post",
          source_id: post.id,
        )
      end

      private

      def ingest(**attributes)
        Delivery.ingest!(**attributes)
      end

      def eligible_user?(user)
        return false if user.blank? || user.bot? || user.suspended?
        return false if SiteSetting.reliable_push_respect_do_not_disturb && user.do_not_disturb?
        true
      end

      def enabled_type?(type)
        symbol = type.to_sym
        return SiteSetting.reliable_push_chat_notifications if CHAT_TYPES.include?(symbol)
        return SiteSetting.reliable_push_post_notifications if POST_TYPES.include?(symbol)
        return SiteSetting.reliable_push_badge_notifications if symbol == :granted_badge
        SiteSetting.reliable_push_other_notifications
      end

      def type_name(value)
        Notification.types[value].to_s.presence || value.to_s
      end

      def dedupe_key(type:, payload:)
        if payload[:chat_message_id].present?
          "chat:#{type}:#{payload[:chat_message_id]}"
        elsif payload[:post_id].present?
          post_dedupe_key(payload[:post_id])
        elsif payload[:topic_id].present? && payload[:post_number].present?
          "topic-post:#{payload[:topic_id]}:#{payload[:post_number]}"
        elsif payload[:notification_id].present?
          "notification:#{payload[:notification_id]}"
        else
          digest = Digest::SHA256.hexdigest(payload.to_json).first(24)
          "event:#{type}:#{digest}"
        end
      end

      def source_type(payload)
        return "Chat::Message" if payload[:chat_message_id].present?
        return "Post" if payload[:post_id].present?
        return "Topic" if payload[:topic_id].present?
        nil
      end

      def source_id(payload)
        payload[:chat_message_id] || payload[:post_id] || payload[:topic_id]
      end

      def post_dedupe_key(post_id)
        "post:#{post_id}"
      end
    end
  end
end
