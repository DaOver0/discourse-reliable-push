# frozen_string_literal: true

module Jobs
  class ReliablePushDeliverAttempt < ::Jobs::Base
    RETRYABLE_CODES = [408, 425, 429].freeze

    def execute(args)
      attempt = ::ReliablePush::Attempt.includes(:delivery, :subscription).find_by(id: args[:attempt_id])
      return if attempt.blank? || attempt.terminal?

      delivery = attempt.delivery
      subscription = attempt.subscription
      return cancel!(attempt, "Delivery no longer available") if delivery.blank? || delivery.terminal?
      return expire!(attempt, delivery) if delivery.expired_by_time?
      return cancel!(attempt, "Subscription disabled") unless subscription&.enabled?
      return cancel!(attempt, "Subscription belongs to another user") if subscription.user_id != delivery.user_id
      unless ::ReliablePush::AccessChecker.allowed?(delivery)
        delivery.update_columns(state: ::ReliablePush::Delivery.states[:cancelled], last_error: "Access check failed")
        return cancel!(attempt, "Access check failed")
      end

      attempt.update_columns(state: ::ReliablePush::Attempt.states[:sending], attempts: attempt.attempts + 1, next_attempt_at: nil)
      message = ::ReliablePush::PayloadBuilder.with_delivery(delivery.payload, delivery)
      ::ReliablePush::Sender.call(subscription:, message:)

      now = Time.zone.now
      attempt.update_columns(state: ::ReliablePush::Attempt.states[:accepted], last_error: nil, last_response_code: nil, updated_at: now)
      subscription.mark_success!
      delivery.mark_accepted!
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
    rescue Timeout::Error, OpenSSL::SSL::SSLError, SocketError, EOFError, Errno::ECONNRESET, Errno::ECONNREFUSED => e
      retry_later!(attempt, e)
    rescue StandardError => e
      retry_later!(attempt, e)
    end

    private

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
      subscription = attempt.subscription
      subscription&.mark_failure!

      if attempt.attempts >= SiteSetting.reliable_push_max_attempts || attempt.delivery.expired_by_time?
        fail_permanently!(attempt, error, code: code)
        return
      end

      delays = setting_list(SiteSetting.reliable_push_retry_delays_seconds).map(&:to_i).select(&:positive?)
      delays = [60, 300, 1800, 7200, 21600, 86400] if delays.blank?
      delay = delays.fetch([attempt.attempts - 1, delays.length - 1].min)
      next_at = delay.seconds.from_now
      attempt.update_columns(
        state: ::ReliablePush::Attempt.states[:retrying],
        next_attempt_at: next_at,
        last_response_code: code,
        last_error: error_summary(error),
      )
      attempt.delivery.update_columns(last_error: error_summary(error))
      Jobs.enqueue_in(delay.seconds, :reliable_push_deliver_attempt, attempt_id: attempt.id)
    end

    def fail_permanently!(attempt, error, state: :failed, code: nil)
      return if attempt.blank?
      attempt.update_columns(
        state: ::ReliablePush::Attempt.states.fetch(state),
        last_response_code: code,
        last_error: error_summary(error),
        next_attempt_at: nil,
      )
      delivery = attempt.delivery
      return if delivery.blank?
      remaining = delivery.attempts.where.not(state: [::ReliablePush::Attempt.states[:failed], ::ReliablePush::Attempt.states[:expired], ::ReliablePush::Attempt.states[:cancelled]])
      delivery.update_columns(state: ::ReliablePush::Delivery.states[:failed], last_error: error_summary(error)) unless remaining.exists?
      Discourse.warn_exception(error, message: "Reliable Push delivery failed", env: { attempt_id: attempt.id, delivery_id: delivery.id })
    end

    def cancel!(attempt, reason)
      attempt.update_columns(state: ::ReliablePush::Attempt.states[:cancelled], last_error: reason)
    end

    def expire!(attempt, delivery)
      attempt.update_columns(state: ::ReliablePush::Attempt.states[:expired], last_error: "Delivery TTL expired")
      delivery.update_columns(state: ::ReliablePush::Delivery.states[:expired])
    end

    def setting_list(value)
      Array(value).flat_map { |item| item.to_s.split("|") }
    end

    def error_summary(error)
      "#{error.class}: #{error.message}".first(4000)
    end
  end
end
