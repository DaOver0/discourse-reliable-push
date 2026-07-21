# frozen_string_literal: true

module Jobs
  class ReliablePushBroadcastNewTopic < ::Jobs::Base
    BATCH_SIZE = 100

    def execute(args)
      post = Post.includes(:topic).find_by(id: args[:post_id])
      return if post.blank? || post.post_number != 1 || post.topic.private_message?

      group_ids = Array(SiteSetting.reliable_push_broadcast_group_ids).flat_map { |item| item.to_s.split("|") }.map(&:to_i).select(&:positive?).uniq
      return if group_ids.blank?

      user_ids = GroupUser.where(group_id: group_ids).where.not(user_id: post.user_id).distinct.limit(SiteSetting.reliable_push_broadcast_max_recipients).pluck(:user_id)

      User.where(id: user_ids).where(active: true, approved: true).merge(User.not_suspended).find_in_batches(batch_size: BATCH_SIZE) do |users|
        users.each do |user|
          next unless Guardian.new(user).can_see?(post.topic)
          ::ReliablePush::EventIngestor.broadcast_new_topic(user:, post:)
        end
      end
    end
  end
end
