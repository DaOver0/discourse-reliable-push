# frozen_string_literal: true

module ReliablePush
  class PayloadBuilder
    class << self
      def from_core_payload(user:, payload:)
        payload = payload.to_h.with_indifferent_access
        type = Notification.types[payload[:notification_type]].to_s.presence || payload[:notification_type].to_s

        I18n.with_locale(user.effective_locale) do
          title = payload[:translated_title].presence || core_title(payload) || translated_title(type)
          build_message(
            title: title,
            body: payload[:excerpt].presence || I18n.t("reliable_push.bodies.generic"),
            url: payload[:post_url],
            tag: payload[:tag].presence || default_tag(type:, payload:),
            actions: payload[:actions],
            action_data: payload[:action_data],
            metadata: payload.slice(:post_id, :topic_id, :post_number, :chat_message_id, :channel_id),
          )
        end
      end

      def from_notification(notification)
        user = notification.user
        type = Notification.types[notification.notification_type].to_s.presence || notification.notification_type.to_s
        data = parse_data(notification.data)
        post = notification_post(notification)

        I18n.with_locale(user.effective_locale) do
          if post
            core_payload = {
              notification_type: notification.notification_type,
              post_number: post.post_number,
              topic_title: post.topic.title,
              topic_id: post.topic_id,
              post_id: post.id,
              excerpt: post.excerpt(
                SiteSetting.reliable_push_excerpt_length,
                text_entities: true,
                strip_links: true,
                remap_emoji: true,
                plain_hashtags: true,
              ),
              username: data["display_username"] || data["original_username"] || post.username,
              group_name: data["group_name"],
              post_url: post.url,
            }
            return from_core_payload(user:, payload: core_payload)
          end

          chat_payload = chat_payload_from_notification(type:, data:)
          return from_core_payload(user:, payload: chat_payload) if chat_payload

          body = generic_notification_body(type:, data:)
          build_message(
            title: translated_title(type),
            body: body,
            url: notification_url(notification, data),
            tag: "#{Discourse.current_hostname}-notification-#{notification.id}",
            metadata: { notification_id: notification.id },
          )
        end
      end

      def for_new_topic_broadcast(user:, post:)
        I18n.with_locale(user.effective_locale) do
          build_message(
            title: I18n.t("reliable_push.titles.broadcast_new_topic"),
            body: post.topic.title,
            url: post.url,
            tag: "#{Discourse.current_hostname}-broadcast-topic-#{post.topic_id}",
            metadata: { post_id: post.id, topic_id: post.topic_id, post_number: post.post_number },
          )
        end
      end

      def for_topic_post_broadcast(user:, post:)
        I18n.with_locale(user.effective_locale) do
          if post.post_number == 1
            return for_new_topic_broadcast(user:, post:)
          end

          build_message(
            title: I18n.t("reliable_push.titles.broadcast_topic_post", topic: post.topic.title),
            body: post.excerpt(
              SiteSetting.reliable_push_excerpt_length,
              text_entities: true,
              strip_links: true,
              remap_emoji: true,
              plain_hashtags: true,
            ),
            url: post.url,
            tag: "#{Discourse.current_hostname}-broadcast-post-#{post.id}",
            metadata: { post_id: post.id, topic_id: post.topic_id, post_number: post.post_number },
          )
        end
      end

      def with_delivery(message, delivery)
        data = message.deep_dup.with_indifferent_access
        ack = {
          delivery_id: delivery.id,
          received_url: "/reliable-push/ack/#{delivery.id}/#{delivery.ack_token}/received",
          opened_url: "/reliable-push/ack/#{delivery.id}/#{delivery.ack_token}/opened",
        }
        data[:reliable_push] = ack
        data[:action_data] = (data[:action_data] || {}).merge(reliable_push: ack)
        data
      end

      private

      def build_message(title:, body:, url:, tag:, actions: nil, action_data: nil, metadata: {})
        message = {
          title: title.to_s,
          body: body.to_s.first(SiteSetting.reliable_push_excerpt_length),
          icon: absolute_url(SiteSetting.site_logo_small_url.presence || PushNotificationPusher.get_badge),
          badge: absolute_url(PushNotificationPusher.get_badge),
          tag: tag,
          base_url: Discourse.base_url,
          url: normalize_url(url),
        }.merge(metadata.compact.stringify_keys)
        message[:actions] = actions if actions.present?
        message[:action_data] = action_data if action_data.present?
        message
      end

      def core_title(payload)
        PushNotificationPusher.title(payload)
      rescue I18n::MissingTranslationData, StandardError
        nil
      end

      def translated_title(type)
        I18n.t("reliable_push.titles.#{type}", default: I18n.t("reliable_push.titles.generic"))
      end

      def generic_notification_body(type:, data:)
        if type == "granted_badge"
          badge = data["badge_name"] || data["name"] || data["display_name"] || ""
          return I18n.t("reliable_push.bodies.badge", badge: badge)
        end

        data["description"].presence || data["topic_title"].presence || data["excerpt"].presence || I18n.t("reliable_push.bodies.generic")
      end

      def chat_payload_from_notification(type:, data:)
        message_id = data["chat_message_id"]
        return if message_id.blank? || !defined?(::Chat::Message)

        message = ::Chat::Message.find_by(id: message_id)
        return if message.blank?

        {
          notification_type: Notification.types[type.to_sym],
          chat_message_id: message.id,
          channel_id: message.chat_channel_id,
          username: message.user&.username,
          translated_title: translated_title(type),
          excerpt: message.push_notification_excerpt,
          post_url: message.url,
          tag: "#{Discourse.current_hostname}-chat-#{message.chat_channel_id}",
        }
      rescue StandardError
        nil
      end

      def notification_post(notification)
        return if notification.topic_id.blank? || notification.post_number.blank?
        Post.find_by(topic_id: notification.topic_id, post_number: notification.post_number)
      end

      def notification_url(notification, data)
        return data["url"] if data["url"].present?
        return "/u/#{notification.user.username}/badges" if Notification.types[notification.notification_type].to_s == "granted_badge"
        "/my/notifications"
      end

      def default_tag(type:, payload:)
        id = payload[:chat_message_id] || payload[:topic_id] || payload[:post_id] || SecureRandom.hex(6)
        "#{Discourse.current_hostname}-#{type}-#{id}"
      end

      def normalize_url(url)
        return "/" if url.blank?
        value = url.to_s.sub(/\A#{Regexp.escape(Discourse.base_url)}/, "")
        value = value.sub(/\A#{Regexp.escape(Discourse.base_path)}/, "") if Discourse.base_path.present?
        value.start_with?("/") ? value : "/#{value}"
      end

      def absolute_url(url)
        return Discourse.base_url if url.blank?
        value = url.to_s
        return value if value.match?(%r{\Ahttps?://}i)
        "#{Discourse.base_url}#{value.start_with?("/") ? "" : "/"}#{value}"
      end

      def parse_data(data)
        return data if data.is_a?(Hash)
        JSON.parse(data.presence || "{}")
      rescue JSON::ParserError
        {}
      end
    end
  end
end
