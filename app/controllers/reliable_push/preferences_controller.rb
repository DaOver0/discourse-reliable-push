# frozen_string_literal: true

module ::ReliablePush
  class PreferencesController < ::ApplicationController
    requires_login

    def show
      render json: { preferences: PreferenceResolver.as_json(current_user) }
    end

    def update
      attributes =
        params
          .require(:preferences)
          .permit(*Preference::FIELDS)
          .to_h

      PreferenceResolver.update!(current_user, attributes)
      render json: {
        success: true,
        preferences: PreferenceResolver.as_json(current_user),
      }
    end
  end
end
