# frozen_string_literal: true

module ::ReliablePush
  class Subscription < ActiveRecord::Base
    self.table_name = "reliable_push_subscriptions"

    belongs_to :user
    has_many :attempts,
             class_name: "ReliablePush::Attempt",
             dependent: :delete_all,
             inverse_of: :subscription

    scope :active, -> { where(enabled: true) }

    validates :user_id, :endpoint_digest, :endpoint, :p256dh, :auth, presence: true
    validates :endpoint_digest, uniqueness: true

    class << self
      def sync!(user:, subscription:, user_agent: nil, allow_reassignment: true)
        data = normalize(subscription)
        endpoint = data["endpoint"].to_s
        keys = normalize(data["keys"])

        raise ArgumentError, "Push subscription endpoint is missing" if endpoint.blank?
        raise ArgumentError, "Push subscription p256dh key is missing" if keys["p256dh"].blank?
        raise ArgumentError, "Push subscription auth key is missing" if keys["auth"].blank?

        digest = Digest::SHA256.hexdigest(endpoint)

        transaction do
          record = lock.find_or_initialize_by(endpoint_digest: digest)
          if record.persisted? && record.user_id != user.id && !allow_reassignment
            next nil
          end

          record.assign_attributes(
            user_id: user.id,
            endpoint: endpoint,
            p256dh: keys["p256dh"],
            auth: keys["auth"],
            user_agent: user_agent.presence || record.user_agent,
            enabled: true,
            failure_count: 0,
            last_failure_at: nil,
          )
          record.save!
          record
        end
      end

      def disable_for_user!(user)
        where(user_id: user.id).update_all(enabled: false, updated_at: Time.zone.now)
      end

      # Existing Discourse subscriptions are imported server-side. This is
      # essential for fanout events: users do not have to reopen the site before
      # new-topic/new-post notifications start working.
      def mirror_core_for_user!(user)
        return 0 unless user.respond_to?(:push_subscriptions)

        count = 0
        user.push_subscriptions.find_each do |core_subscription|
          parsed =
            if core_subscription.respond_to?(:parsed_data)
              core_subscription.parsed_data
            elsif core_subscription.respond_to?(:data)
              JSON.parse(core_subscription.data.to_s)
            end

          next if parsed.blank?

          mirrored =
            sync!(
              user: user,
              subscription: parsed,
              user_agent:
                core_subscription.respond_to?(:user_agent) ? core_subscription.user_agent : nil,
              allow_reassignment: false,
            )
          count += 1 if mirrored
        rescue JSON::ParserError, ArgumentError => e
          Rails.logger.warn(
            "[ReliablePush] skipped malformed core subscription #{core_subscription.id}: #{e.message}",
          )
        end

        count
      end

      private

      def normalize(value)
        hash =
          if value.respond_to?(:to_unsafe_h)
            value.to_unsafe_h
          elsif value.respond_to?(:to_h)
            value.to_h
          else
            value || {}
          end

        hash.deep_stringify_keys
      end
    end

    def disable!
      now = Time.zone.now
      self.class.where(id: id).update_all(
        [
          <<~SQL.squish,
            enabled = FALSE,
            failure_count = failure_count + 1,
            last_failure_at = ?,
            updated_at = ?
          SQL
          now,
          now,
        ],
      )
    end

    def mark_success!
      update_columns(
        enabled: true,
        failure_count: 0,
        last_success_at: Time.zone.now,
        last_failure_at: nil,
        updated_at: Time.zone.now,
      )
    end

    def mark_failure!
      now = Time.zone.now
      self.class.where(id: id).update_all(
        [
          <<~SQL.squish,
            failure_count = failure_count + 1,
            last_failure_at = ?,
            updated_at = ?
          SQL
          now,
          now,
        ],
      )
    end
  end
end
