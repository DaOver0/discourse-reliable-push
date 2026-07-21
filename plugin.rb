# frozen_string_literal: true

# name: discourse-reliable-push
# about: Durable, policy-aware Web Push delivery for Discourse, Chat, account events, categories, and Resenha rooms.
# version: 0.3.0
# authors: DaOver0
# url: https://github.com/DaOver0/discourse-reliable-push
# required_version: 3.4.0

enabled_site_setting :reliable_push_enabled

register_asset "stylesheets/reliable-push.scss"
register_service_worker "assets/service-worker/reliable-push.js"

after_initialize do
  module ::ReliablePush
    PLUGIN_NAME = "discourse-reliable-push"
  end

  require_relative "lib/reliable_push/engine"

  [
    "app/models/reliable_push/subscription",
    "app/models/reliable_push/delivery",
    "app/models/reliable_push/attempt",
    "app/models/reliable_push/preference",
    "app/services/reliable_push/result",
    "app/services/reliable_push/preference_resolver",
    "app/services/reliable_push/recipient_scope",
    "app/services/reliable_push/access_checker",
    "app/services/reliable_push/payload_builder",
    "app/services/reliable_push/event_ingestor",
    "app/services/reliable_push/sender",
    "app/services/reliable_push/push_notification_pusher_extension",
    "app/services/reliable_push/resenha_participant_tracker_extension",
    "app/jobs/regular/reliable_push_prepare_delivery",
    "app/jobs/regular/reliable_push_deliver_attempt",
    "app/jobs/regular/reliable_push_broadcast_topic_post",
    "app/jobs/regular/reliable_push_broadcast_category",
    "app/jobs/regular/reliable_push_broadcast_resenha_join",
    "app/jobs/scheduled/reliable_push_cleanup",
    "app/jobs/scheduled/reliable_push_recover_stale_attempts",
    "app/controllers/reliable_push/subscriptions_controller",
    "app/controllers/reliable_push/preferences_controller",
    "app/controllers/reliable_push/acknowledgements_controller",
    "app/controllers/reliable_push/status_controller",
    "app/controllers/reliable_push/admin/status_controller",
  ].each { |path| require_relative path }

  reloadable_patch do
    # safe_constantize also triggers Rails autoloading. That matters for
    # optional plugins such as Resenha, whose classes may not have been
    # referenced yet when this plugin's initializer runs.
    push_pusher = "PushNotificationPusher".safe_constantize
    if push_pusher
      push_singleton = push_pusher.singleton_class
      unless push_singleton < ::ReliablePush::PushNotificationPusherExtension
        push_singleton.prepend(::ReliablePush::PushNotificationPusherExtension)
      end
    end

    participant_tracker = "Resenha::ParticipantTracker".safe_constantize
    if participant_tracker
      tracker_singleton = participant_tracker.singleton_class
      unless tracker_singleton < ::ReliablePush::ResenhaParticipantTrackerExtension
        tracker_singleton.prepend(::ReliablePush::ResenhaParticipantTrackerExtension)
      end
    end
  end

  add_to_serializer(:current_user, :reliable_push_preferences) do
    ::ReliablePush::PreferenceResolver.as_json(object)
  end

  Discourse::Application.routes.append do
    mount ::ReliablePush::Engine, at: "/reliable-push"
  end

  # PostAlerter emits this before it decides whether the core browser/hub
  # delivery job should be enqueued. Capturing it here keeps personal events
  # reliable even when only the plugin-owned mirror still has a valid endpoint.
  on(:push_notification) do |user, payload|
    next unless SiteSetting.reliable_push_enabled
    next unless SiteSetting.reliable_push_replace_core_web_push

    ::ReliablePush::EventIngestor.from_core_push(user: user, payload: payload)
  rescue StandardError => e
    Rails.logger.error(
      "[ReliablePush] push_notification ingestion failed: #{e.class}: #{e.message}",
    )
  end

  on(:notification_created) do |notification|
    next unless SiteSetting.reliable_push_enabled
    next unless SiteSetting.reliable_push_replace_core_web_push

    ::ReliablePush::EventIngestor.from_notification(notification)
  rescue StandardError => e
    Rails.logger.error(
      "[ReliablePush] notification_created ingestion failed: #{e.class}: #{e.message}",
    )
  end

  on(:post_alerter_after_save_post) do |post, new_record, _notified_users|
    next unless SiteSetting.reliable_push_enabled
    next unless new_record
    next unless SiteSetting.reliable_push_topic_events_enabled

    if post.post_number == 1
      next unless SiteSetting.reliable_push_new_topics_enabled
    else
      next unless SiteSetting.reliable_push_topic_posts_enabled
    end

    Jobs.enqueue(:reliable_push_broadcast_topic_post, post_id: post.id)
  rescue StandardError => e
    Rails.logger.error(
      "[ReliablePush] topic-post fanout enqueue failed: #{e.class}: #{e.message}",
    )
  end

  on(:category_created) do |category|
    next unless SiteSetting.reliable_push_enabled
    next unless SiteSetting.reliable_push_new_categories_enabled

    Jobs.enqueue(:reliable_push_broadcast_category, category_id: category.id)
  rescue StandardError => e
    Rails.logger.error(
      "[ReliablePush] category fanout enqueue failed: #{e.class}: #{e.message}",
    )
  end

  resenha_handler = lambda do |room_or_id, user_or_id|
    next unless SiteSetting.reliable_push_enabled
    next unless SiteSetting.reliable_push_resenha_enabled

    room_id = room_or_id.respond_to?(:id) ? room_or_id.id : room_or_id
    user_id = user_or_id.respond_to?(:id) ? user_or_id.id : user_or_id

    Jobs.enqueue(
      :reliable_push_broadcast_resenha_join,
      room_id: room_id.to_i,
      joining_user_id: user_id.to_i,
    )
  rescue StandardError => e
    Rails.logger.error(
      "[ReliablePush] Resenha fanout enqueue failed: #{e.class}: #{e.message}",
    )
  end

  on(:reliable_push_resenha_joined, &resenha_handler)
  on(:resenha_user_joined_room, &resenha_handler)
  on(:resenha_participant_joined, &resenha_handler)
end
