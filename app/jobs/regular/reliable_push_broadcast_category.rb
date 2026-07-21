# frozen_string_literal: true

module Jobs
  class ReliablePushBroadcastCategory < ::Jobs::Base
    def execute(args)
      category = Category.find_by(id: args[:category_id])
      return if category.blank?

      ::ReliablePush::RecipientScope
        .users(
          group_setting: SiteSetting.reliable_push_category_group_ids,
          exclude_user_id: category.user_id,
        )
        .find_each(batch_size: 250) do |user|
          ::ReliablePush::EventIngestor.new_category(user: user, category: category)
        rescue StandardError => e
          Discourse.warn_exception(
            e,
            message: "Reliable Push category fanout failed for one recipient",
            env: { user_id: user.id, category_id: category.id },
          )
        end
    end
  end
end
