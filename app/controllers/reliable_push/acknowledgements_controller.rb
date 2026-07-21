# frozen_string_literal: true

module ReliablePush
  class AcknowledgementsController < ::ApplicationController
    requires_plugin ReliablePush::PLUGIN_NAME
    skip_before_action :preload_json
    skip_before_action :verify_authenticity_token

    def received
      delivery = authenticated_delivery
      return head :not_found if delivery.blank?

      delivery.mark_received!
      head :no_content
    end

    def opened
      delivery = authenticated_delivery
      return head :not_found if delivery.blank?

      delivery.mark_opened!
      head :no_content
    end

    private

    def authenticated_delivery
      delivery = Delivery.find_by(id: params[:delivery_id])
      return if delivery.blank?

      supplied = params[:token].to_s
      expected = delivery.ack_token.to_s
      return if supplied.bytesize != expected.bytesize
      return unless ActiveSupport::SecurityUtils.secure_compare(supplied, expected)

      delivery
    end
  end
end
