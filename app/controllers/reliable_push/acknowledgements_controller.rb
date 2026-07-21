# frozen_string_literal: true

module ::ReliablePush
  class AcknowledgementsController < ::ApplicationController
    skip_before_action :verify_authenticity_token

    def received
      acknowledge!(:received)
    end

    def opened
      acknowledge!(:opened)
    end

    private

    def acknowledge!(kind)
      token = params[:token].presence
      token ||= request.request_parameters["token"] if request.request_parameters.respond_to?(:[])
      delivery = Delivery.find_by(ack_token: token)

      if delivery.blank?
        render json: { success: false }, status: :not_found
        return
      end

      kind == :opened ? delivery.mark_opened! : delivery.mark_received!
      render json: { success: true }
    end
  end
end
