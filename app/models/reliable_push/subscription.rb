# frozen_string_literal: true

module ReliablePush
  class Subscription < ActiveRecord::Base
    self.table_name = "reliable_push_subscriptions"

    belongs_to :user
    has_many :attempts, class_name: "ReliablePush::Attempt", dependent: :delete_all

    validates :endpoint, :endpoint_digest, :p256dh, :auth, presence: true
    validates :endpoint_digest, uniqueness: true

    scope :active, -> { where(enabled: true) }

    def self.digest(endpoint)
      Digest::SHA256.hexdigest(endpoint.to_s)
    end

    def self.sync!(user:, subscription:, user_agent: nil)
      return nil if subscription.blank?

      endpoint = subscription[:endpoint].presence || subscription["endpoint"].presence
      keys = subscription[:keys].presence || subscription["keys"].presence || {}
      p256dh = keys[:p256dh].presence || keys["p256dh"].presence
      auth = keys[:auth].presence || keys["auth"].presence
      raise ArgumentError, "Invalid PushSubscription" if endpoint.blank? || p256dh.blank? || auth.blank?

      digest = self.digest(endpoint)
      record = find_or_initialize_by(endpoint_digest: digest)
      record.assign_attributes(
        user: user,
        endpoint: endpoint,
        p256dh: p256dh,
        auth: auth,
        user_agent: user_agent.to_s.first(1000),
        enabled: true,
        failure_count: 0,
      )
      record.save!

      record
    end

    def mark_success!
      update_columns(failure_count: 0, last_success_at: Time.zone.now, last_failure_at: nil, enabled: true)
    end

    def mark_failure!
      update_columns(failure_count: failure_count + 1, last_failure_at: Time.zone.now)
    end

    def disable!
      update_columns(enabled: false, last_failure_at: Time.zone.now)
    end
  end
end
