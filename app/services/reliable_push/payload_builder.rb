# frozen_string_literal: true

module ::ReliablePush
  class PayloadBuilder
    class << self
      def from_core_payload(user:, payload:)
        input = normalize(payload)
        type = notification_type_name(input["notification_type"] || input["type"])

        I18n.with_locale(user.effective_locale) do
          title =
            input["translated_title"].presence ||
              core_title(input) ||
              translated_title(type)

          build_message(
            title: title,
            body: input["excerpt"].presence || input["body"].presence || I18n.t("reliable_push.generic_body"),
            url: input["post_url"].presence || input["url"],
            tag: input["tag"].presence || default_tag(type: type, payload: input),
            actions: input["actions"],
            action_data: input["action_data"] || input["actionData"],
            metadata:
              input.slice(
                "notification_id",
                "post_id",
                "topic_id",
                "post_number",
                "chat_message_id",
                "chat_channel_id",
                "channel_id",
              ),
          )
        end
      end

      def from_notification(notification)
        user = notification.user
        type = notification_type_name(notification.notification_type)
        data = parse_notification_data(notification.data)
        post = notification_post(notification, data)

        I18n.with_locale(user.effective_locale) do
          if post
            return from_core_payload(
              user: user,
              payload: {
                notification_type: notification.notification_type,
                notification_id: notification.id,
                post_number: post.post_number,
                topic_title: post.topic.title,
                topic_id: post.topic_id,
                post_id: post.id,
                excerpt: post_excerpt(post),
                username:
                  data["display_username"] ||
                    data["original_username"] ||
                    post.user&.username,
                group_name: data["group_name"],
                post_url: post.url,
              },
            )
          end

          chat_payload = chat_payload_from_notification(type: type, data: data, notification: notification)
          return from_core_payload(user: user, payload: chat_payload) if chat_payload

          build_message(
            title: notification_title(type, data),
            body: generic_notification_body(type: type, data: data),
            url: notification_url(notification, data, type),
            tag: "#{Discourse.current_hostname}-notification-#{notification.id}",
            metadata: {
              "notification_id" => notification.id,
              "topic_id" => notification.topic_id,
              "chat_message_id" => data["chat_message_id"],
              "chat_channel_id" => data["chat_channel_id"] || data["channel_id"],
            }.compact,
          )
        end
      end

      def for_topic_post(post:, kind:)
        topic = post.topic
        author = post.user&.username || I18n.t("reliable_push.unknown_user")
        new_topic = kind.to_s == "new_topic"

        build_message(
          title:
            new_topic ?
              I18n.t("reliable_push.new_topic_title", site_name: SiteSetting.title) :
              I18n.t("reliable_push.new_post_title", topic: topic.title),
          body:
            I18n.t(
              new_topic ? "reliable_push.new_topic_body" : "reliable_push.new_post_body",
              username: author,
              excerpt: post_excerpt(post),
            ),
          url: post.url,
          tag: "#{Discourse.current_hostname}-post-#{post.id}",
          metadata: {
            "post_id" => post.id,
            "topic_id" => topic.id,
            "post_number" => post.post_number,
            "category_id" => topic.category_id,
          },
        )
      end

      def for_category(category:)
        build_message(
          title: I18n.t("reliable_push.new_category_title", site_name: SiteSetting.title),
          body: I18n.t("reliable_push.new_category_body", category: category.name),
          url: category.url,
          tag: "#{Discourse.current_hostname}-category-#{category.id}",
          metadata: { "category_id" => category.id },
        )
      end

      def for_resenha(room:, joining_user:)
        room_name =
          if room.respond_to?(:name)
            room.name
          elsif room.respond_to?(:title)
            room.title
          else
            I18n.t("reliable_push.voice_room")
          end

        url =
          if room.respond_to?(:relative_url)
            room.relative_url
          elsif room.respond_to?(:slug)
            "/resenha/r/#{room.slug}"
          else
            "/resenha"
          end

        build_message(
          title: I18n.t("reliable_push.resenha_join_title", room: room_name),
          body:
            I18n.t(
              "reliable_push.resenha_join_body",
              username: joining_user.username,
              room: room_name,
            ),
          url: url,
          tag: "#{Discourse.current_hostname}-resenha-#{room.id}-#{joining_user.id}",
          metadata: {
            "resenha_room_id" => room.id,
            "joining_user_id" => joining_user.id,
          },
        )
      end

      def with_delivery(payload, delivery)
        message = normalize(payload).deep_dup
        metadata = {
          "token" => delivery.ack_token,
          "delivery_id" => delivery.id,
          "received_url" => "#{Discourse.base_url}/reliable-push/ack/received",
          "opened_url" => "#{Discourse.base_url}/reliable-push/ack/opened",
        }

        # Root metadata is visible to the service worker's push handler.
        message["reliable_push"] = metadata

        # action_data is copied into Notification.data by Discourse's service
        # worker, which makes the token available on notificationclick.
        action_data = normalize(message["action_data"] || message["actionData"])
        action_data["reliable_push"] = metadata
        action_data["reliablePush"] = metadata
        message["action_data"] = action_data
        message
      end

      def live_payload(delivery)
        value = normalize(delivery.payload)

        {
          delivery_id: delivery.id,
          kind: delivery.kind,
          title: value["title"],
          body: value["body"],
          url: absolute_url(value["url"]),
          preference_key: value["preference_key"],
          sound: PreferenceResolver.sound?(delivery.user),
          tab_blink: PreferenceResolver.tab_blink?(delivery.user),
        }
      end

      private

      def build_message(title:, body:, url:, tag:, actions: nil, action_data: nil, metadata: {})
        message = {
          "title" => plain_text(title),
          "body" => plain_text(body).first(SiteSetting.reliable_push_excerpt_length),
          "icon" => default_icon,
          "badge" => default_badge,
          "tag" => tag,
          "base_url" => Discourse.base_url,
          "url" => normalize_url(url),
          "renotify" => true,
          "silent" => false,
        }.merge(normalize(metadata).compact)

        message["actions"] = actions if actions.present?
        message["action_data"] = action_data if action_data.present?
        message
      end

      def core_title(payload)
        ::PushNotificationPusher.title(payload.symbolize_keys)
      rescue I18n::MissingTranslationData, StandardError
        nil
      end

      def translated_title(type)
        case type
        when "granted_badge"
          I18n.t("reliable_push.badge_title")
        when "chat_message", "chat_mention", "chat_quoted", "chat_watched_thread"
          I18n.t("reliable_push.chat_title")
        when "mentioned", "group_mentioned", "replied", "quoted"
          I18n.t("reliable_push.mention_title")
        when "private_message", "invited_to_private_message"
          I18n.t("reliable_push.private_message_title")
        else
          SiteSetting.title
        end
      end

      def notification_title(type, data)
        data["title"].presence || translated_title(type)
      end

      def generic_notification_body(type:, data:)
        if type == "granted_badge"
          badge = data["badge_name"] || data["name"] || data["display_name"] || ""
          return badge.present? ? badge : I18n.t("reliable_push.generic_body")
        end

        plain_text(
          data["description"].presence ||
            data["message"].presence ||
            data["topic_title"].presence ||
            data["excerpt"].presence ||
            (data["display_username"].present? ?
               I18n.t("reliable_push.notification_from", username: data["display_username"]) :
               I18n.t("reliable_push.generic_body")),
        )
      end

      def chat_payload_from_notification(type:, data:, notification:)
        message_id = data["chat_message_id"]
        return if message_id.blank? || !defined?(::Chat::Message)

        message = ::Chat::Message.find_by(id: message_id)
        return if message.blank?

        {
          notification_type: notification.notification_type,
          notification_id: notification.id,
          chat_message_id: message.id,
          channel_id: message.chat_channel_id,
          username: message.user&.username,
          translated_title: translated_title(type),
          excerpt:
            message.respond_to?(:push_notification_excerpt) ?
              message.push_notification_excerpt :
              message.message.to_s,
          post_url: message.respond_to?(:url) ? message.url : "/chat",
          tag: "#{Discourse.current_hostname}-chat-#{message.chat_channel_id}",
        }
      rescue StandardError
        nil
      end

      def notification_post(notification, data)
        post_id = data["post_id"]
        return Post.find_by(id: post_id) if post_id.present?

        topic_id = notification.topic_id || data["topic_id"]
        post_number =
          (notification.post_number if notification.respond_to?(:post_number)).presence ||
            data["post_number"]
        return if topic_id.blank? || post_number.blank?

        Post.find_by(topic_id: topic_id, post_number: post_number)
      end

      def notification_url(notification, data, type)
        return data["url"] if data["url"].present?
        return "/u/#{notification.user.username}/badges" if type == "granted_badge"

        "/my/notifications"
      end

      def post_excerpt(post)
        if post.respond_to?(:excerpt)
          return post.excerpt(
            SiteSetting.reliable_push_excerpt_length,
            text_entities: true,
            strip_links: true,
            remap_emoji: true,
            plain_hashtags: true,
          )
        end

        text = ActionController::Base.helpers.strip_tags(post.cooked.to_s)
        plain_text(text).truncate(SiteSetting.reliable_push_excerpt_length)
      end

      def default_tag(type:, payload:)
        id =
          payload["chat_message_id"] ||
            payload["topic_id"] ||
            payload["post_id"] ||
            payload["notification_id"] ||
            SecureRandom.hex(6)
        "#{Discourse.current_hostname}-#{type}-#{id}"
      end

      def notification_type_name(value)
        mapping = Notification.types
        string_value = value.to_s
        return string_value if mapping.key?(string_value)

        numeric = Integer(value, exception: false)
        mapping.key(numeric).to_s.presence || string_value
      rescue StandardError
        value.to_s
      end

      def default_icon
        value =
          SiteSetting.site_logo_small_url.presence ||
            SiteSetting.site_mobile_logo_url.presence ||
            ::PushNotificationPusher.get_badge
        absolute_url(value)
      rescue StandardError
        default_badge
      end

      def default_badge
        absolute_url(::PushNotificationPusher.get_badge)
      rescue StandardError
        "#{Discourse.base_url}/images/d-logo-sketch-small.png"
      end

      def normalize_url(url)
        return "/" if url.blank?

        value = url.to_s.sub(/\A#{Regexp.escape(Discourse.base_url)}/, "")
        if Discourse.base_path.present?
          value = value.sub(/\A#{Regexp.escape(Discourse.base_path)}/, "")
        end
        value.start_with?("/") ? value : "/#{value}"
      end

      def absolute_url(url)
        return Discourse.base_url if url.blank?

        value = url.to_s
        return value if value.match?(%r{\Ahttps?://}i)

        "#{Discourse.base_url}#{value.start_with?("/") ? "" : "/"}#{value}"
      end

      def plain_text(value)
        value.to_s.gsub(/\s+/, " ").strip
      end

      def parse_notification_data(value)
        return normalize(value) if value.is_a?(Hash)

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
