# frozen_string_literal: true

module ::ReliablePush
  class PreferenceResolver
    SITE_SETTINGS = {
      topic_posts: :reliable_push_topic_posts_enabled,
      new_topics: :reliable_push_new_topics_enabled,
      chat_messages: :reliable_push_chat_enabled,
      mentions_replies: :reliable_push_mentions_replies_enabled,
      private_messages: :reliable_push_private_messages_enabled,
      badges: :reliable_push_badges_enabled,
      account_events: :reliable_push_account_events_enabled,
      new_categories: :reliable_push_new_categories_enabled,
      resenha: :reliable_push_resenha_enabled,
      other: :reliable_push_other_events_enabled,
    }.freeze

    class << self
      def enabled?(user, key)
        key = key.to_sym
        return false unless SiteSetting.reliable_push_enabled

        site_setting = SITE_SETTINGS[key]
        return false if site_setting && !SiteSetting.public_send(site_setting)
        return false unless legacy_site_setting_enabled?(key)

        record = Preference.find_by(user_id: user.id)
        record.nil? || record.public_send(key)
      end

      def sound?(user)
        record = Preference.find_by(user_id: user.id)
        record ? record.sound? : SiteSetting.reliable_push_default_sound
      end

      def tab_blink?(user)
        record = Preference.find_by(user_id: user.id)
        record ? record.tab_blink? : SiteSetting.reliable_push_default_tab_blink
      end

      def as_json(user)
        record = Preference.find_by(user_id: user.id)

        Preference::EVENT_FIELDS.index_with do |field|
          enabled?(user, field)
        end.merge(
          sound: record ? record.sound? : SiteSetting.reliable_push_default_sound,
          tab_blink:
            record ? record.tab_blink? : SiteSetting.reliable_push_default_tab_blink,
        )
      end

      def update!(user, attributes)
        permitted = attributes.to_h.symbolize_keys.slice(*Preference::FIELDS)
        record = Preference.find_or_initialize_by(user_id: user.id)
        record.assign_attributes(permitted)
        record.save!
        record
      end

      private

      def legacy_site_setting_enabled?(key)
        case key.to_sym
        when :topic_posts, :new_topics, :mentions_replies, :private_messages
          SiteSetting.reliable_push_post_notifications
        when :chat_messages
          SiteSetting.reliable_push_chat_notifications
        when :badges
          SiteSetting.reliable_push_badge_notifications
        when :account_events, :other
          SiteSetting.reliable_push_other_notifications
        else
          true
        end
      end
    end
  end
end
