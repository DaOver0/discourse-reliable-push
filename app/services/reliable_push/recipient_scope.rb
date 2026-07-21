# frozen_string_literal: true

module ::ReliablePush
  class RecipientScope
    class << self
      def users(group_setting: nil, exclude_user_id: nil)
        relation = User.where(id: push_user_ids)
        relation = relation.where(active: true, staged: false)
        relation = relation.where(approved: true) if User.column_names.include?("approved")
        relation = relation.where("users.id > 0")
        relation =
          relation.where(
            "users.suspended_till IS NULL OR users.suspended_till < ?",
            Time.zone.now,
          )

        group_ids = parse_group_ids(group_setting)
        relation = relation.where(id: GroupUser.where(group_id: group_ids).select(:user_id)) if group_ids.any?
        relation = relation.where.not(id: exclude_user_id) if exclude_user_id.present?

        relation.distinct.limit(SiteSetting.reliable_push_max_fanout)
      end

      def push_user_ids
        mirrored = Subscription.active.select(:user_id)
        return mirrored unless defined?(::PushSubscription)

        core = ::PushSubscription.select(:user_id)
        User.where(id: mirrored).or(User.where(id: core)).select(:id)
      end

      def parse_group_ids(value)
        Array(value)
          .flat_map { |item| item.to_s.split(/[|,;]/) }
          .map(&:strip)
          .select { |item| item.match?(/\A\d+\z/) }
          .map(&:to_i)
          .uniq
      end
    end
  end
end
