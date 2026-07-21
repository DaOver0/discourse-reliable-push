# frozen_string_literal: true

module ::ReliablePush
  module ResenhaParticipantTrackerExtension
    def add(room_id, user_id, ...)
      was_present =
        begin
          Array(user_ids(room_id)).map(&:to_i).include?(user_id.to_i)
        rescue StandardError
          true
        end

      result = super

      unless was_present
        DiscourseEvent.trigger(
          :reliable_push_resenha_joined,
          room_id.to_i,
          user_id.to_i,
        )
      end

      result
    end
  end
end
