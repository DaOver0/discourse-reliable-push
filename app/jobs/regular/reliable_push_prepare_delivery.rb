# frozen_string_literal: true

module Jobs
  class ReliablePushPrepareDelivery < ::Jobs::Base
    def execute(args)
      delivery = ::ReliablePush::Delivery.find_by(id: args[:delivery_id])
      return if delivery.blank? || delivery.terminal?

      if delivery.expired_by_time?
        delivery.update_columns(state: ::ReliablePush::Delivery.states[:expired])
        return
      end

      unless ::ReliablePush::AccessChecker.allowed?(delivery)
        delivery.update_columns(state: ::ReliablePush::Delivery.states[:cancelled], last_error: "Access check failed")
        return
      end

      delivery.update_columns(state: ::ReliablePush::Delivery.states[:preparing]) if delivery.pending?
      subscriptions = ::ReliablePush::Subscription.active.where(user_id: delivery.user_id)

      if subscriptions.blank?
        delivery.update_columns(state: ::ReliablePush::Delivery.states[:no_subscription])
        return
      end

      subscriptions.find_each do |subscription|
        attempt = ::ReliablePush::Attempt.find_or_create_by!(delivery_id: delivery.id, subscription_id: subscription.id)
        Jobs.enqueue(:reliable_push_deliver_attempt, attempt_id: attempt.id) unless attempt.terminal?
      end
    end
  end
end
