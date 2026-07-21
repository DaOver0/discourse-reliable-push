# frozen_string_literal: true

module ReliablePush
  class AccessChecker
    def self.allowed?(delivery)
      user = delivery.user
      return false if user.blank? || user.suspended? || !user.active?
      return false if SiteSetting.reliable_push_respect_do_not_disturb && user.do_not_disturb?

      payload = delivery.payload.with_indifferent_access
      guardian = Guardian.new(user)

      if payload[:topic_id].present?
        topic = Topic.find_by(id: payload[:topic_id])
        return false if topic.blank? || !guardian.can_see?(topic)
      end

      if payload[:channel_id].present? && defined?(::Chat::Channel)
        channel = ::Chat::Channel.find_by(id: payload[:channel_id])
        return false if channel.blank?
        return false if guardian.respond_to?(:can_join_chat_channel?) && !guardian.can_join_chat_channel?(channel)
      end

      true
    rescue StandardError => e
      Discourse.warn_exception(e, message: "Reliable Push access check failed", env: { delivery_id: delivery.id })
      false
    end
  end
end
