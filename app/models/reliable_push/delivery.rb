# frozen_string_literal: true

module ReliablePush
  class Delivery < ActiveRecord::Base
    self.table_name = "reliable_push_deliveries"

    belongs_to :user
    has_many :attempts, class_name: "ReliablePush::Attempt", dependent: :delete_all

    enum :state, { pending: 0, preparing: 1, accepted: 2, received: 3, opened: 4, no_subscription: 5, expired: 6, failed: 7, cancelled: 8 }

    validates :kind, :dedupe_key, :ack_token, :expires_at, presence: true
    validates :dedupe_key, uniqueness: { scope: :user_id }
    validates :ack_token, uniqueness: true

    before_validation :ensure_ack_token, on: :create

    def self.ingest!(user:, kind:, dedupe_key:, payload:, priority:, source_type: nil, source_id: nil)
      delivery = find_or_initialize_by(user_id: user.id, dedupe_key: dedupe_key)
      is_new = delivery.new_record?

      if is_new || priority.to_i >= delivery.priority
        delivery.assign_attributes(
          kind: kind,
          payload: payload,
          priority: priority,
          source_type: source_type,
          source_id: source_id,
          expires_at: SiteSetting.reliable_push_delivery_ttl_hours.hours.from_now,
        )
      end

      should_enqueue = is_new
      if !is_new && delivery.no_subscription? && !delivery.expired_by_time? && Subscription.active.where(user_id: user.id).exists?
        delivery.state = :pending
        should_enqueue = true
      elsif is_new
        delivery.state = :pending
      end

      delivery.save!
      Jobs.enqueue(:reliable_push_prepare_delivery, delivery_id: delivery.id) if should_enqueue
      delivery
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def terminal?
      no_subscription? || expired? || failed? || cancelled? || opened?
    end

    def expired_by_time?
      expires_at <= Time.zone.now
    end

    def mark_accepted!
      now = Time.zone.now
      attributes = { accepted_at: accepted_at || now, last_error: nil }
      attributes[:state] = self.class.states[:accepted] if pending? || preparing? || accepted?
      update_columns(attributes)
    end

    def mark_received!
      attributes = { received_at: received_at || Time.zone.now }
      attributes[:state] = self.class.states[:received] unless opened?
      update_columns(attributes)
    end

    def mark_opened!
      now = Time.zone.now
      update_columns(state: self.class.states[:opened], received_at: received_at || now, opened_at: opened_at || now)
    end

    private

    def ensure_ack_token
      self.ack_token ||= SecureRandom.hex(24)
    end
  end
end
