# frozen_string_literal: true

module Jobs
  class ReliablePushPrepareDelivery < ::Jobs::Base
    def execute(args)
      delivery = ::ReliablePush::Delivery.includes(:user).find_by(id: args[:delivery_id])
      return if delivery.blank? || delivery.terminal? || delivery.delivered?

      if delivery.expired_by_time?
        ::ReliablePush::Delivery
          .where(id: delivery.id, state: %i[pending preparing no_subscription failed])
          .update_all(
            state: ::ReliablePush::Delivery.states[:expired],
            last_error: "Delivery TTL expired before preparation",
            updated_at: Time.zone.now,
          )
        return
      end

      return unless claim_preparation!(delivery)

      unless ::ReliablePush::AccessChecker.allowed?(delivery)
        delivery.update_columns(
          state: ::ReliablePush::Delivery.states[:cancelled],
          last_error: "Recipient, preference, ACL, mute, or DND policy rejected delivery",
          updated_at: Time.zone.now,
        )
        return
      end

      ::ReliablePush::Subscription.mirror_core_for_user!(delivery.user)
      subscriptions =
        ::ReliablePush::Subscription.active.where(user_id: delivery.user_id).to_a

      if subscriptions.blank?
        delivery.update_columns(
          state: ::ReliablePush::Delivery.states[:no_subscription],
          last_error: "No active browser push subscription",
          updated_at: Time.zone.now,
        )
        return
      end

      subscriptions.each do |subscription|
        attempt =
          ::ReliablePush::Attempt.find_or_create_by!(
            delivery_id: delivery.id,
            subscription_id: subscription.id,
          ) do |record|
            record.state = :pending
          end

        if attempt.failed? || attempt.expired? || attempt.cancelled?
          attempt.update_columns(
            state: ::ReliablePush::Attempt.states[:pending],
            attempts: 0,
            next_attempt_at: nil,
            last_response_code: nil,
            last_error: nil,
            updated_at: Time.zone.now,
          )
        end

        next if attempt.terminal? || attempt.sending? || attempt.retrying?

        Jobs.enqueue(:reliable_push_deliver_attempt, attempt_id: attempt.id)
      end
    rescue StandardError => e
      if delivery
        ::ReliablePush::Delivery
          .where(id: delivery.id, state: %i[pending preparing no_subscription])
          .update_all(
            state: ::ReliablePush::Delivery.states[:failed],
            last_error: "#{e.class}: #{e.message}".first(4000),
            updated_at: Time.zone.now,
          )
      end
      raise
    end

    private

    def claim_preparation!(delivery)
      now = Time.zone.now
      ::ReliablePush::Delivery
        .where(id: delivery.id, state: %i[pending no_subscription])
        .update_all(
          state: ::ReliablePush::Delivery.states[:preparing],
          last_error: nil,
          updated_at: now,
        ) == 1
    end
  end
end
