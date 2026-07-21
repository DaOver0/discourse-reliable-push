# frozen_string_literal: true

# name: discourse-reliable-push
# about: Durable, observable Web Push delivery for Discourse notifications.
# version: 0.1.0
# authors: DaOver0 and contributors
# url: https://github.com/DaOver0/discourse-reliable-push
# required_version: 3.4.0

enabled_site_setting :reliable_push_enabled

register_service_worker "service-worker/reliable-push.js"

module ::ReliablePush
  PLUGIN_NAME = "discourse-reliable-push"
end

require_relative "lib/reliable_push/engine"

after_initialize do
  on(:push_notification) do |user, payload|
    ReliablePush::EventIngestor.from_core_push(user:, payload:)
  end

  on(:notification_created) do |notification|
    ReliablePush::EventIngestor.from_notification(notification)
  end

  on(:post_created) do |post, _opts = nil, _user = nil|
    next unless SiteSetting.reliable_push_broadcast_new_topics
    next unless post.post_number == 1
    next if post.topic&.private_message?

    Jobs.enqueue(:reliable_push_broadcast_new_topic, post_id: post.id)
  end

  reloadable_patch do
    PushNotificationPusher.singleton_class.prepend(ReliablePush::PushNotificationPusherExtension)
  end
end
