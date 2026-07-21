# frozen_string_literal: true

module Jobs
  class ReliablePushRecoverStaleAttempts < ::Jobs::Scheduled
    every 10.minutes

    def execute(_args)
      timeout =
        [
          SiteSetting.reliable_push_open_timeout_seconds.to_i +
            SiteSetting.reliable_push_read_timeout_seconds.to_i +
            60,
          5.minutes.to_i,
        ].max
      stale_before = timeout.seconds.ago

      recover_deliveries(stale_before)
      recover_attempts(stale_before)
      recover_unqueued_work(stale_before)
    end

    private

    def recover_deliveries(stale_before)
      ::ReliablePush::Delivery
        .where(state: :preparing)
        .where("updated_at < ?", stale_before)
        .find_each(batch_size: 100) do |delivery|
          now = Time.zone.now

          if delivery.expired_by_time?
            ::ReliablePush::Delivery
              .where(id: delivery.id, state: :preparing)
              .update_all(
                state: ::ReliablePush::Delivery.states[:expired],
                last_error: "Delivery TTL expired while preparation was stale",
                updated_at: now,
              )
            next
          end

          recovered =
            ::ReliablePush::Delivery
              .where(id: delivery.id, state: :preparing)
              .update_all(
                state: ::ReliablePush::Delivery.states[:pending],
                last_error: "Recovered stale preparation",
                updated_at: now,
              )
          Jobs.enqueue(:reliable_push_prepare_delivery, delivery_id: delivery.id) if recovered == 1
        end
    end

    def recover_attempts(stale_before)
      ::ReliablePush::Attempt
        .includes(:delivery)
        .where(state: :sending)
        .where("reliable_push_attempts.updated_at < ?", stale_before)
        .find_each(batch_size: 100) do |attempt|
          delivery = attempt.delivery
          now = Time.zone.now

          if delivery.blank? || delivery.terminal? || delivery.expired_by_time?
            ::ReliablePush::Attempt
              .where(id: attempt.id, state: :sending)
              .update_all(
                state: ::ReliablePush::Attempt.states[:cancelled],
                last_error: "Stale sending attempt belongs to an unavailable delivery",
                next_attempt_at: nil,
                updated_at: now,
              )
            next
          end

          recovered =
            ::ReliablePush::Attempt
              .where(id: attempt.id, state: :sending)
              .update_all(
                state: ::ReliablePush::Attempt.states[:retrying],
                last_error: "Recovered stale sending attempt",
                next_attempt_at: now,
                updated_at: now,
              )
          Jobs.enqueue(:reliable_push_deliver_attempt, attempt_id: attempt.id) if recovered == 1
        end
    end

    # Jobs.enqueue and Redis are not a distributed transaction with PostgreSQL.
    # Re-scan old pending rows and overdue retries so a process crash between
    # the database write and queue insertion does not strand the delivery.
    # Atomic claims in the regular jobs make duplicate enqueueing harmless.
    def recover_unqueued_work(stale_before)
      ::ReliablePush::Delivery
        .where(state: :pending)
        .where("updated_at < ?", stale_before)
        .find_each(batch_size: 100) do |delivery|
          Jobs.enqueue(:reliable_push_prepare_delivery, delivery_id: delivery.id)
        end

      ::ReliablePush::Attempt
        .where(state: :pending)
        .where("updated_at < ?", stale_before)
        .or(
          ::ReliablePush::Attempt
            .where(state: :retrying)
            .where("next_attempt_at IS NULL OR next_attempt_at <= ?", Time.zone.now),
        )
        .find_each(batch_size: 100) do |attempt|
          Jobs.enqueue(:reliable_push_deliver_attempt, attempt_id: attempt.id)
        end
    end
  end
end
