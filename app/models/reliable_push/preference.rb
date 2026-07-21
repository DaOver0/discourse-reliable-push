# frozen_string_literal: true

module ::ReliablePush
  class Preference < ActiveRecord::Base
    self.table_name = "reliable_push_preferences"

    belongs_to :user

    EVENT_FIELDS = %i[
      topic_posts
      new_topics
      chat_messages
      mentions_replies
      private_messages
      badges
      account_events
      new_categories
      resenha
      other
    ].freeze

    PRESENTATION_FIELDS = %i[sound tab_blink].freeze
    FIELDS = (EVENT_FIELDS + PRESENTATION_FIELDS).freeze

    validates :user_id, uniqueness: true
  end
end
