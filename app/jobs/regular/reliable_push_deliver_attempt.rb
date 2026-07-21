# frozen_string_literal: true

module Jobs
  class ReliablePushDeliverAttempt < ::Jobs::Base
    RETRYABLE_CODES = [408, 425, 429].freeze
    DELIVERABLE_ATTEMPT_STATES = %i[pending sending retrying accepted].freeze

    def execute(args)
      attempt =
        ::ReliablePush::Attempt.includes(:delivery, :subscription).find_by(
          id: args[:attempt_id],
        )
      return if attempt.blank? || attempt.terminal?

      delivery = attempt.delivery
      subscription = attempt.subscription

      return cancel!(attempt, "Delivery no longer exists") if delivery.blank?
      return cancel!(attempt, "Delivery is terminal") if delivery.terminal?
      return expire!(attempt, delivery) if delivery.expired_by_time?
      return cancel!(attempt, "Subscription disabled") unless subscription&.enabled?
      return cancel!(attempt, "Subscription owner mismatch") if subscription.user_id != delivery.user_id

      unless ::ReliablePush::AccessChecker.allowed?(delivery)
        ::ReliablePush::Delivery
          .where(id: delivery.id, state: %i[pending preparing no_subscription failed])
          .update_all(
            state: ::ReliablePush::Delivery.states[:cancelled],
            last_error: "Access policy rejected delivery at send time",
            updated_at: Time.zone.now,
          )
        return cancel!(attempt, "Access policy rejected delivery")
      end

      return unless claim!(attempt)

      attempt.reload

      message = ::ReliablePush::PayloadBuilder.with_delivery(delivery.payload, delivery)
      ::ReliablePush::Sender.call(subscription: subscription, message: message)

      now = Time.zone.now
      attempt.update_columns(
        state: ::ReliablePush::Attempt.states[:accepted],
        last_error: nil,
        last_response_code: nil,
        updated_at: now,
      )
      # Persist the logical success before non-essential bookkeeping. A
      # logging/event-hook failure after the push service accepted the payload
      # must not schedule a duplicate Web Push.
      delivery.mark_accepted!
      subscription.mark_success!
      DiscourseEvent.trigger(:reliable_push_accepted, delivery, subscription)
    rescue WebPush::ExpiredSubscription => e
      subscription&.disable!
      fail_permanently!(attempt, e, state: :expired)
    rescue WebPush::ResponseError => e
      code = response_code(e)
      if [404, 410].include?(code)
        subscription&.disable!
        fail_permanently!(attempt, e, state: :expired, code: code)
      elsif retryable_code?(code)
        retry_later!(attempt, e, code: code)
      else
        fail_permanently!(attempt, e, code: code)
      end
    rescue Timeout::Error,
           OpenSSL::SSL::SSLError,
           SocketError,
           EOFError,
           Errno::ECONNRESET,
           Errno::ECONNREFUSED => e
      retry_later!(attempt, e)
    rescue StandardError => e
      retry_later!(attempt, e)
    end

    private

    def claim!(attempt)
      now = Time.zone.now
      pending = ::ReliablePush::Attempt.states[:pending]
      retrying = ::ReliablePush::Attempt.states[:retrying]
      sending = ::ReliablePush::Attempt.states[:sending]

      ::ReliablePush::Attempt
        .where(id: attempt.id)
        .where(
          "state = :pending OR (state = :retrying AND (next_attempt_at IS NULL OR next_attempt_at <= :now))",
          pending: pending,
          retrying: retrying,
          now: now,
        )
        .update_all(
          [
            "state = ?, attempts = attempts + 1, next_attempt_at = NULL, updated_at = ?",
            sending,
            now,
          ],
        ) == 1
    end

    def retryable_code?(code)
      code.blank? || RETRYABLE_CODES.include?(code) || code >= 500
    end

    def response_code(error)
      response = error.respond_to?(:response) ? error.response : nil
      value = response.respond_to?(:code) ? response.code : nil
      value.to_i if value.present?
    end

    def retry_later!(attempt, error, code: nil)
      return if attempt.blank?

      attempt.reload
      # The push may already have been accepted and only later bookkeeping
      # failed. Never turn an accepted attempt back into a retry.
      return if attempt.terminal?

      delivery = attempt.delivery
      return cancel!(attempt, "Delivery no longer exists") if delivery.blank?

      attempt.subscription&.mark_failure!
      if attempt.attempts >= SiteSetting.reliable_push_max_attempts ||
           delivery.expired_by_time?
        fail_permanently!(attempt, error, code: code)
        return
      end

      configured_delays =
        Array(SiteSetting.reliable_push_retry_delays_seconds)
          .flat_map { |value| value.to_s.split(/[|,;]/) }
          .map(&:to_i)
          .select(&:positive?)

      delay =
        if configured_delays.any?
          configured_delays.fetch(
            [attempt.attempts - 1, configured_delays.length - 1].min,
          )
        else
          base = [SiteSetting.reliable_push_retry_base_seconds.to_i, 5].max
          exponent = [attempt.attempts - 1, 10].min
          [base * (2**exponent), 24.hours.to_i].min
        end
      delay += rand(0..[delay / 5, 1].max)

      attempt.update_columns(
        state: ::ReliablePush::Attempt.states[:retrying],
        next_attempt_at: delay.seconds.from_now,
        last_response_code: code,
        last_error: error_summary(error),
        updated_at: Time.zone.now,
      )
      ::ReliablePush::Delivery
        .where(id: delivery.id, state: %i[pending preparing no_subscription failed])
        .update_all(
          last_error: error_summary(error),
          updated_at: Time.zone.now,
        )

      Jobs.enqueue_in(delay.seconds, :reliable_push_deliver_attempt, attempt_id: attempt.id)
    end

    def fail_permanently!(attempt, error, state: :failed, code: nil)
      return if attempt.blank?

      attempt.reload
      return if attempt.accepted?

      attempt.update_columns(
        state: ::ReliablePush::Attempt.states.fetch(state),
        last_response_code: code,
        last_error: error_summary(error),
        next_attempt_at: nil,
        updated_at: Time.zone.now,
      )

      delivery = attempt.delivery
      finalize_delivery_if_exhausted!(
        attempt,
        error_summary(error),
        preferred_state: :failed,
      )

      return if delivery.blank?

      Discourse.warn_exception(
        error,
        message: "Reliable Push delivery attempt failed",
        env: { attempt_id: attempt.id, delivery_id: delivery.id },
      )
    end

    def cancel!(attempt, reason)
      attempt.update_columns(
        state: ::ReliablePush::Attempt.states[:cancelled],
        last_error: reason,
        next_attempt_at: nil,
        updated_at: Time.zone.now,
      )
      finalize_delivery_if_exhausted!(attempt, reason, preferred_state: :failed)
    end

    def finalize_delivery_if_exhausted!(attempt, reason, preferred_state:)
      delivery = attempt.delivery
      return if delivery.blank? || delivery.delivered? || delivery.cancelled? || delivery.expired?

      still_possible =
        delivery
          .attempts
          .where(state: DELIVERABLE_ATTEMPT_STATES)
          .where.not(id: attempt.id)
          .exists?
      return if still_possible

      active_subscription =
        ::ReliablePush::Subscription.active.where(user_id: delivery.user_id).exists?
      final_state = active_subscription ? preferred_state : :no_subscription

      ::ReliablePush::Delivery
        .where(id: delivery.id, state: %i[pending preparing no_subscription failed])
        .update_all(
          state: ::ReliablePush::Delivery.states.fetch(final_state),
          last_error: reason,
          updated_at: Time.zone.now,
        )
    end

    def expire!(attempt, delivery)
      attempt.update_columns(
        state: ::ReliablePush::Attempt.states[:expired],
        last_error: "Delivery TTL expired",
        next_attempt_at: nil,
        updated_at: Time.zone.now,
      )
      ::ReliablePush::Delivery
        .where(id: delivery.id, state: %i[pending preparing no_subscription failed])
        .update_all(
          state: ::ReliablePush::Delivery.states[:expired],
          last_error: "Delivery TTL expired",
          updated_at: Time.zone.now,
        )
    end

    def error_summary(error)
      "#{error.class}: #{error.message}".first(4000)
    end
  end
end
