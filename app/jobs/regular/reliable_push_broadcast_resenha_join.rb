# frozen_string_literal: true

module Jobs
  class ReliablePushBroadcastResenhaJoin < ::Jobs::Base
    def execute(args)
      return unless defined?(::Resenha::Room)

      room = ::Resenha::Room.find_by(id: args[:room_id])
      joining_user = User.find_by(id: args[:joining_user_id])
      return if room.blank? || joining_user.blank?

      ::ReliablePush::RecipientScope
        .users(
          group_setting: SiteSetting.reliable_push_resenha_group_ids,
          exclude_user_id: joining_user.id,
        )
        .find_each(batch_size: 250) do |user|
          ::ReliablePush::EventIngestor.resenha_join(
            user: user,
            room: room,
            joining_user: joining_user,
          )
        rescue StandardError => e
          Discourse.warn_exception(
            e,
            message: "Reliable Push Resenha fanout failed for one recipient",
            env: {
              user_id: user.id,
              room_id: room.id,
              joining_user_id: joining_user.id,
            },
          )
        end
    end
  end
end
