# frozen_string_literal: true

module Jobs
  class ReliablePushBroadcastTopicPost < ::Jobs::Base
    def execute(args)
      post = Post.includes(:topic, :user).find_by(id: args[:post_id])
      return if post.blank? || post.topic.blank?
      return if post.deleted_at.present?
      return if post.respond_to?(:hidden?) && post.hidden?
      return if post.post_type != Post.types[:regular]
      return if post.topic.private_message?
      return unless post.topic.visible?
      return if Category.exists?(topic_id: post.topic_id)

      group_setting = SiteSetting.reliable_push_topic_group_ids
      if group_setting.blank?
        group_setting =
          post.post_number == 1 ?
            SiteSetting.reliable_push_broadcast_group_ids :
            SiteSetting.reliable_push_all_topic_posts_group_ids
      end

      ::ReliablePush::RecipientScope
        .users(group_setting: group_setting, exclude_user_id: post.user_id)
        .find_each(batch_size: 250) do |user|
          ::ReliablePush::EventIngestor.topic_post(user: user, post: post)
        rescue StandardError => e
          Discourse.warn_exception(
            e,
            message: "Reliable Push topic fanout failed for one recipient",
            env: { user_id: user.id, post_id: post.id },
          )
        end
    end
  end
end
