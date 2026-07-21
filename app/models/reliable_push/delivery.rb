# frozen_string_literal: true

module ::ReliablePush
  class Delivery < ActiveRecord::Base
    self.table_name = "reliable_push_deliveries"

    belongs_to :user
    has_many :attempts,
             class_name: "ReliablePush::Attempt",
             dependent: :delete_all,
             inverse_of: :delivery

    enum :state,
         {
           pending: 0,
           preparing: 1,
           accepted: 2,
           received: 3,
           opened: 4,
           no_subscription: 5,
           expired: 6,
           failed: 7,
           cancelled: 8,
         }

    validates :user_id, :kind, :dedupe_key, :ack_token, :expires_at, presence: true
    validates :dedupe_key, uniqueness: { scope: :user_id }
    validates :ack_token, uniqueness: true

    scope :live, -> { where.not(state: %i[cancelled failed expired opened]) }

    class << self
      # Returns [delivery, changed]. A higher-priority semantic duplicate
      # upgrades the stored payload rather than creating another notification.
      def ingest!(user:, kind:, dedupe_key:, payload:, priority:, source_type: nil, source_id: nil)
        now = Time.zone.now
        expires_at = SiteSetting.reliable_push_delivery_ttl_hours.hours.from_now

        delivery =
          create!(
            user_id: user.id,
            kind: kind,
            source_type: source_type,
            source_id: source_id,
            dedupe_key: dedupe_key,
            payload: payload,
            priority: priority,
            state: :pending,
            ack_token: SecureRandom.urlsafe_base64(32),
            expires_at: expires_at,
          )

        [delivery, true]
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
        raise unless duplicate_error?(e)

        transaction do
          # Serialize semantic upgrades. Without the row lock, two concurrent
          # personal events could both read the old priority and the lower one
          # could overwrite the higher-priority payload.
          delivery = lock.find_by!(user_id: user.id, dedupe_key: dedupe_key)
          changed = false

          if priority.to_i > delivery.priority.to_i && !delivery.opened?
            attributes = {
              kind: kind,
              source_type: source_type,
              source_id: source_id,
              payload: payload,
              priority: priority,
              expires_at: [delivery.expires_at, expires_at].compact.max,
            }

            if delivery.failed? || delivery.cancelled? || delivery.expired?
              attributes[:state] = :pending
              attributes[:last_error] = nil
            end

            delivery.update!(attributes)
            changed = true
          end

          [delivery, changed]
        end
      end

      private

      def duplicate_error?(error)
        return true if error.is_a?(ActiveRecord::RecordNotUnique)

        error.record&.errors&.of_kind?(:dedupe_key, :taken)
      end
    end

    def terminal?
      cancelled? || failed? || expired? || opened?
    end

    # A delivery which reached the push service must not be sent through the
    # preparation phase again. Other already-enqueued device attempts may
    # still finish independently.
    def delivered?
      accepted? || received? || opened?
    end

    def expired_by_time?
      expires_at.present? && expires_at <= Time.zone.now
    end

    def mark_accepted!
      now = Time.zone.now
      accepted = self.class.states[:accepted]
      received = self.class.states[:received]
      opened = self.class.states[:opened]

      self.class.where(id: id).update_all(
        [
          <<~SQL.squish,
            state = CASE WHEN state IN (?, ?) THEN state ELSE ? END,
            accepted_at = COALESCE(accepted_at, ?),
            last_error = NULL,
            updated_at = ?
          SQL
          received,
          opened,
          accepted,
          now,
          now,
        ],
      )
    end

    def mark_received!
      now = Time.zone.now
      received = self.class.states[:received]
      opened = self.class.states[:opened]

      self.class.where(id: id).update_all(
        [
          <<~SQL.squish,
            state = CASE WHEN state = ? THEN state ELSE ? END,
            received_at = COALESCE(received_at, ?),
            updated_at = ?
          SQL
          opened,
          received,
          now,
          now,
        ],
      )
    end

    def mark_opened!
      now = Time.zone.now
      opened = self.class.states[:opened]

      self.class.where(id: id).update_all(
        [
          <<~SQL.squish,
            state = ?,
            received_at = COALESCE(received_at, ?),
            opened_at = COALESCE(opened_at, ?),
            updated_at = ?
          SQL
          opened,
          now,
          now,
          now,
        ],
      )
    end
  end
end
