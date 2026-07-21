# frozen_string_literal: true

module Jobs
  class ReliablePushBroadcastTopicPost < ::Jobs::Base
    BATCH_SIZE = 100

    def execute(args)
      post = Post.includes(:topic).find_by(id: args[:post_id])
      return unless eligible_post?(post)

      recipient_ids(post).each_slice(BATCH_SIZE) do |user_ids|
        User.where(id: user_ids).includes(:do_not_disturb_timings).each do |user|
          ::ReliablePush::EventIngestor.broadcast_topic_post(user:, post:)
        end
      end
    end

    private

    def eligible_post?(post)
      return false if post.blank? || post.deleted_at.present? || post.hidden?
      return false unless post.post_type == Post.types[:regular]

      topic = post.topic
      return false if topic.blank? || topic.deleted_at.present?
      return false if topic.private_message? || !topic.visible?

      true
    end

    def recipient_ids(post)
      scope =
        User
          .where(id: ::ReliablePush::Subscription.active.select(:user_id))
          .where(active: true, approved: true, staged: false)
          .where.not(id: post.user_id)
          .merge(User.not_suspended)

      group_ids = setting_ids(SiteSetting.reliable_push_all_topic_posts_group_ids)
      if group_ids.present?
        scope = scope.joins(:group_users).where(group_users: { group_id: group_ids })
      end

      scope
        .distinct
        .order(:id)
        .limit(SiteSetting.reliable_push_all_topic_posts_max_recipients)
        .pluck(:id)
    end

    def setting_ids(value)
      Array(value)
        .flat_map { |item| item.to_s.split("|") }
        .map(&:to_i)
        .select(&:positive?)
        .uniq
    end
  end
end
