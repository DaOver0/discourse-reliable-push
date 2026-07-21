# frozen_string_literal: true

module ::ReliablePush
  class Result
    attr_reader :status, :delivery, :error

    def initialize(status:, delivery: nil, error: nil)
      @status = status
      @delivery = delivery
      @error = error
    end

    def handled?
      status == :handled
    end

    def suppressed?
      status == :suppressed
    end

    def failed?
      status == :failed
    end

    class << self
      def handled(delivery = nil)
        new(status: :handled, delivery: delivery)
      end

      def suppressed
        new(status: :suppressed)
      end

      def failed(error = nil)
        new(status: :failed, error: error)
      end
    end
  end
end
