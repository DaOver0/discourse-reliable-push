# frozen_string_literal: true

module ::ReliablePush
  class EventIngestor
    CHAT_TYPES = %w[
      chat_message
      chat_mention
      chat_invitation
      chat_quoted
      chat_watched_thread
    ].freeze

    MENTION_REPLY_TYPES = %w[
      mentioned
      group_mentioned
      replied
      quoted
      chat_mention
      chat_quoted
    ].freeze

    PRIVATE_MESSAGE_TYPES = %w[
      private_message
      invited_to_private_message
    ].freeze

    ACCOUNT_TYPES = %w[
      liked
      linked
      edited
      bookmark_reminder
      following
      following_created_topic
      moved_post
      custom
    ].freeze

    PRIORITIES = {
      "chat_mention" => 110,
      "mentioned" => 110,
      "chat_quoted" => 108,
      "group_mentioned" => 105,
      "private_message" => 100,
      "invited_to_private_message" => 100,
      "replied" => 95,
      "quoted" => 90,
      "chat_message" => 85,
      "chat_watched_thread" => 80,
      "chat_invitation" => 80,
      "posted" => 70,
      "watching_category_or_tag" => 70,
      "watching_first_post" => 65,
      "new_topic" => 50,
      "topic_post" => 45,
      "new_category" => 35,
      "granted_badge" => 35,
      "resenha_join" => 30,
    }.freeze

    class << self
      def from_core_push(user:, payload:)
        return Result.suppressed unless AccessChecker.eligible_user?(user)

        normalized = normalize(payload)
        type = type_name(normalized["notification_type"] || normalized["type"])
        attach_recent_notification_id!(user: user, type: type, payload: normalized)
        preference_key = preference_key_for(type, payload: normalized)
        return Result.suppressed unless PreferenceResolver.enabled?(user, preference_key)

        message = PayloadBuilder.from_core_payload(user: user, payload: normalized)
        message["preference_key"] = preference_key.to_s

        ingest(
          user: user,
          kind: type,
          preference_key: preference_key,
          dedupe_key: dedupe_key(type: type, payload: normalized),
          payload: message,
          priority: PRIORITIES.fetch(type, 20),
          source_type: source_type(normalized),
          source_id: source_id(normalized),
        )
      rescue StandardError => e
        Discourse.warn_exception(
          e,
          message: "Reliable Push failed to ingest core push",
          env: { user_id: user&.id },
        )
        Result.failed(e)
      end

      def from_notification(notification)
        user = notification.user
        return Result.suppressed unless AccessChecker.eligible_user?(user)

        type = type_name(notification.notification_type)
        notification_data = parse_notification_data(notification.data)
        if notification.respond_to?(:post_number)
          notification_data["post_number"] ||= notification.post_number
        end
        preference_key = preference_key_for(type, payload: notification_data)
        return Result.suppressed unless PreferenceResolver.enabled?(user, preference_key)

        payload = PayloadBuilder.from_notification(notification)
        payload["preference_key"] = preference_key.to_s
        semantic =
          normalize(payload).merge(normalize(payload["data"])).merge(
            "notification_id" => notification.id,
            "topic_id" => notification.topic_id,
          )

        ingest(
          user: user,
          kind: type,
          preference_key: preference_key,
          dedupe_key: dedupe_key(type: type, payload: semantic),
          payload: payload,
          priority: PRIORITIES.fetch(type, 20),
          source_type: notification_source_type(notification, semantic),
          source_id: notification_source_id(notification, semantic),
        )
      rescue StandardError => e
        Discourse.warn_exception(
          e,
          message: "Reliable Push failed to ingest notification",
          env: { notification_id: notification&.id },
        )
        Result.failed(e)
      end

      def topic_post(user:, post:)
        kind = post.post_number == 1 ? "new_topic" : "topic_post"
        preference_key = post.post_number == 1 ? :new_topics : :topic_posts
        return Result.suppressed unless PreferenceResolver.enabled?(user, preference_key)
        return Result.suppressed unless AccessChecker.allowed_topic_post?(user: user, post: post)

        payload =
          I18n.with_locale(user.effective_locale) do
            PayloadBuilder.for_topic_post(post: post, kind: kind)
          end
        payload["preference_key"] = preference_key.to_s

        ingest(
          user: user,
          kind: kind,
          preference_key: preference_key,
          dedupe_key: "post:#{post.id}",
          payload: payload,
          priority: PRIORITIES.fetch(kind),
          source_type: "Post",
          source_id: post.id,
        )
      end

      def new_category(user:, category:)
        return Result.suppressed unless PreferenceResolver.enabled?(user, :new_categories)
        return Result.suppressed unless AccessChecker.allowed_category?(user: user, category: category)

        payload =
          I18n.with_locale(user.effective_locale) do
            PayloadBuilder.for_category(category: category)
          end
        payload["preference_key"] = "new_categories"

        ingest(
          user: user,
          kind: "new_category",
          preference_key: :new_categories,
          dedupe_key: "category:created:#{category.id}",
          payload: payload,
          priority: PRIORITIES.fetch("new_category"),
          source_type: "Category",
          source_id: category.id,
        )
      end

      def resenha_join(user:, room:, joining_user:)
        return Result.suppressed unless PreferenceResolver.enabled?(user, :resenha)
        return Result.suppressed unless AccessChecker.allowed_resenha_room?(user: user, room: room)

        bucket =
          Time.zone.now.to_i /
            [SiteSetting.reliable_push_resenha_join_cooldown_seconds.to_i, 30].max
        payload =
          I18n.with_locale(user.effective_locale) do
            PayloadBuilder.for_resenha(room: room, joining_user: joining_user)
          end
        payload["preference_key"] = "resenha"

        ingest(
          user: user,
          kind: "resenha_join",
          preference_key: :resenha,
          dedupe_key: "resenha:join:#{room.id}:#{joining_user.id}:#{bucket}",
          payload: payload,
          priority: PRIORITIES.fetch("resenha_join"),
          source_type: "Resenha::Room",
          source_id: room.id,
        )
      end

      private

      def ingest(user:, kind:, preference_key:, dedupe_key:, payload:, priority:, source_type:, source_id:)
        return Result.suppressed unless AccessChecker.eligible_user?(user)
        return Result.suppressed unless PreferenceResolver.enabled?(user, preference_key)

        delivery, changed =
          Delivery.ingest!(
            user: user,
            kind: kind,
            dedupe_key: dedupe_key,
            payload: payload,
            priority: priority,
            source_type: source_type,
            source_id: source_id,
          )

        if changed || delivery.pending? || delivery.no_subscription?
          Jobs.enqueue(:reliable_push_prepare_delivery, delivery_id: delivery.id)
        end
        publish_live(delivery) if changed

        Result.handled(delivery)
      end

      def publish_live(delivery)
        MessageBus.publish(
          "/reliable-push/#{delivery.user_id}",
          PayloadBuilder.live_payload(delivery),
          user_ids: [delivery.user_id],
        )
      rescue StandardError => e
        Rails.logger.warn(
          "[ReliablePush] live presentation publish failed for delivery #{delivery.id}: #{e.message}",
        )
      end

      def preference_key_for(type, payload: {})
        return :mentions_replies if MENTION_REPLY_TYPES.include?(type)
        return :chat_messages if CHAT_TYPES.include?(type)
        return :private_messages if PRIVATE_MESSAGE_TYPES.include?(type)
        return :badges if type == "granted_badge"
        return :new_topics if type == "watching_first_post"
        return :topic_posts if type == "posted"

        if type == "watching_category_or_tag"
          value = normalize(payload)
          return value["post_number"].to_i == 1 ? :new_topics : :topic_posts
        end

        return :account_events if ACCOUNT_TYPES.include?(type)

        :other
      end

      def attach_recent_notification_id!(user:, type:, payload:)
        return if payload["notification_id"].present?
        return if payload["post_id"].present? || payload["chat_message_id"].present?

        numeric_type = Notification.types[type]
        return if numeric_type.blank?

        notification =
          Notification
            .where(user_id: user.id, notification_type: numeric_type)
            .where("created_at > ?", 5.minutes.ago)
            .order(id: :desc)
            .first
        payload["notification_id"] = notification.id if notification
      rescue StandardError
        nil
      end

      def type_name(value)
        mapping = Notification.types
        string_value = value.to_s

        return string_value if mapping.key?(string_value)

        numeric = Integer(value, exception: false)
        mapping.key(numeric).to_s.presence || string_value.presence || "other"
      rescue StandardError
        value.to_s.presence || "other"
      end

      def dedupe_key(type:, payload:)
        value = normalize(payload)
        data = normalize(value["data"])
        merged = value.merge(data)

        if merged["chat_message_id"].present?
          "chat:#{type}:#{merged["chat_message_id"]}"
        elsif merged["post_id"].present?
          "post:#{merged["post_id"]}"
        elsif merged["topic_id"].present? && merged["post_number"].present?
          "topic-post:#{merged["topic_id"]}:#{merged["post_number"]}"
        elsif merged["notification_id"].present?
          "notification:#{merged["notification_id"]}"
        else
          digest = Digest::SHA256.hexdigest(value.to_json).first(24)
          "event:#{type}:#{digest}"
        end
      end

      def source_type(payload)
        value = normalize(payload)
        data = normalize(value["data"])
        merged = value.merge(data)
        return "Chat::Message" if merged["chat_message_id"].present?
        return "Post" if merged["post_id"].present?
        return "Topic" if merged["topic_id"].present?

        nil
      end

      def source_id(payload)
        value = normalize(payload)
        data = normalize(value["data"])
        merged = value.merge(data)
        merged["chat_message_id"] || merged["post_id"] || merged["topic_id"]
      end

      def notification_source_type(notification, semantic)
        return "Chat::Message" if semantic["chat_message_id"].present?
        return "Post" if semantic["post_id"].present?
        return "Topic" if notification.topic_id.present?

        "Notification"
      end

      def notification_source_id(notification, semantic)
        semantic["chat_message_id"] ||
          semantic["post_id"] ||
          notification.topic_id ||
          notification.id
      end

      def parse_notification_data(value)
        return normalize(value) if value.is_a?(Hash) || value.respond_to?(:to_unsafe_h)

        JSON.parse(value.to_s).deep_stringify_keys
      rescue JSON::ParserError
        {}
      end

      def normalize(value)
        hash =
          if value.respond_to?(:to_unsafe_h)
            value.to_unsafe_h
          elsif value.respond_to?(:to_h)
            value.to_h
          else
            value || {}
          end
        hash.deep_stringify_keys
      end
    end
  end
end
