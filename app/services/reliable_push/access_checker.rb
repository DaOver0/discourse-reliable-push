# frozen_string_literal: true

module ::ReliablePush
  class AccessChecker
    class << self
      def eligible_user?(user)
        return false if user.blank?
        return false if user.id.to_i <= 0
        return false if user.respond_to?(:bot?) && user.bot?
        return false if user.respond_to?(:active?) && !user.active?
        return false if user.respond_to?(:staged?) && user.staged?
        return false if user.respond_to?(:suspended?) && user.suspended?
        return false if user.respond_to?(:approved?) && !user.approved?
        if SiteSetting.reliable_push_respect_do_not_disturb
          return false if do_not_disturb?(user)
        end

        true
      end

      def allowed?(delivery)
        user = delivery.user
        return false unless eligible_user?(user)

        preference_key = delivery.payload["preference_key"] || delivery.payload[:preference_key]
        return false if preference_key.present? && !PreferenceResolver.enabled?(user, preference_key)

        case delivery.source_type
        when "Post"
          post = Post.find_by(id: delivery.source_id)
          return false if post.blank? || post.topic.blank?
          return false if post.deleted_at.present?
          return false if post.respond_to?(:hidden?) && post.hidden?

          if %w[topic_posts new_topics].include?(preference_key.to_s)
            allowed_topic_post?(user: user, post: post)
          else
            Guardian.new(user).can_see?(post.topic)
          end
        when "Topic"
          topic = Topic.find_by(id: delivery.source_id)
          return false if topic.blank?

          if %w[topic_posts new_topics].include?(preference_key.to_s)
            allowed_topic?(user: user, topic: topic)
          else
            Guardian.new(user).can_see?(topic)
          end
        when "Category"
          category = Category.find_by(id: delivery.source_id)
          category.present? && allowed_category?(user: user, category: category)
        when "Chat::Message"
          message =
            defined?(::Chat::Message) ? ::Chat::Message.find_by(id: delivery.source_id) : nil
          message.present? && allowed_chat_message?(user: user, message: message)
        when "Resenha::Room"
          room = find_resenha_room(delivery.source_id)
          room.present? && allowed_resenha_room?(user: user, room: room)
        when "Notification"
          Notification.exists?(id: delivery.source_id, user_id: user.id)
        else
          true
        end
      end

      def allowed_topic_post?(user:, post:)
        return false if post.user_id == user.id
        return false if post.deleted_at.present?
        return false if post.respond_to?(:hidden?) && post.hidden?
        return false if post.post_type != Post.types[:regular]
        return false unless post.topic
        return false if post.topic.private_message?
        return false unless post.topic.visible?
        return false if Category.exists?(topic_id: post.topic_id)
        return false unless Guardian.new(user).can_see?(post.topic)
        return false if muted_for_topic_context?(user: user, topic: post.topic)

        true
      end

      def allowed_topic?(user:, topic:)
        return false unless Guardian.new(user).can_see?(topic)
        return false if muted_for_topic_context?(user: user, topic: topic)

        true
      end

      def allowed_category?(user:, category:)
        guardian = Guardian.new(user)
        visible =
          if guardian.respond_to?(:can_see_category?)
            guardian.can_see_category?(category)
          else
            guardian.can_see?(category)
          end
        return false unless visible

        muted_level = notification_level(:category, :muted)
        return true if muted_level.nil?

        !CategoryUser.exists?(
          user_id: user.id,
          category_id: category.id,
          notification_level: muted_level,
        )
      end

      def allowed_chat_message?(user:, message:)
        return false if message.respond_to?(:deleted_at) && message.deleted_at.present?
        return false if message.respond_to?(:user_id) && message.user_id == user.id

        channel =
          if message.respond_to?(:chat_channel)
            message.chat_channel
          elsif message.respond_to?(:chat_channel_id) && defined?(::Chat::Channel)
            ::Chat::Channel.find_by(id: message.chat_channel_id)
          end
        return false if channel.blank?

        guardian = Guardian.new(user)
        return guardian.can_join_chat_channel?(channel) if guardian.respond_to?(:can_join_chat_channel?)
        return guardian.can_preview_chat_channel?(channel) if guardian.respond_to?(:can_preview_chat_channel?)

        false
      rescue StandardError
        false
      end

      def allowed_resenha_room?(user:, room:)
        guardian = Guardian.new(user)
        return guardian.can_see_resenha_room?(room) if guardian.respond_to?(:can_see_resenha_room?)

        guardian.can_see?(room)
      rescue StandardError
        false
      end

      def muted_for_topic_context?(user:, topic:)
        topic_level = TopicUser.find_by(user_id: user.id, topic_id: topic.id)&.notification_level
        topic_muted = notification_level(:topic, :muted)
        return true if topic_muted.present? && topic_level == topic_muted

        category_muted = category_muted?(user, topic.category_id)
        tag_muted = tags_muted?(user, topic)

        return false unless category_muted || tag_muted

        watching = notification_level(:topic, :watching)
        precedence =
          user.user_option&.respond_to?(:watched_precedence_over_muted) &&
            user.user_option.watched_precedence_over_muted

        !(precedence && watching.present? && topic_level == watching)
      end

      private

      def do_not_disturb?(user)
        return user.do_not_disturb? if user.respond_to?(:do_not_disturb?)
        return user.in_do_not_disturb? if user.respond_to?(:in_do_not_disturb?)

        if user.respond_to?(:do_not_disturb_timings)
          now = Time.zone.now
          return user.do_not_disturb_timings
            .where("starts_at <= ? AND ends_at >= ?", now, now)
            .exists?
        end

        false
      rescue StandardError
        false
      end

      def category_muted?(user, category_id)
        return false if category_id.blank?

        muted = notification_level(:category, :muted)
        muted.present? &&
          CategoryUser.exists?(
            user_id: user.id,
            category_id: category_id,
            notification_level: muted,
          )
      end

      def tags_muted?(user, topic)
        return false unless defined?(::TagUser)
        return false unless topic.respond_to?(:tags)

        tag_ids = topic.tags.pluck(:id)
        return false if tag_ids.blank?

        muted = notification_level(:tag, :muted)
        muted.present? &&
          TagUser.exists?(
            user_id: user.id,
            tag_id: tag_ids,
            notification_level: muted,
          )
      end

      def notification_level(scope, name)
        klass =
          case scope
          when :topic
            TopicUser
          when :category
            CategoryUser
          when :tag
            defined?(::TagUser) ? TagUser : nil
          end
        klass&.notification_levels&.[](name)
      rescue StandardError
        nil
      end

      def find_resenha_room(id)
        return nil unless defined?(::Resenha::Room)

        ::Resenha::Room.find_by(id: id)
      end
    end
  end
end
