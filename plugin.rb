# frozen_string_literal: true
# name: discourse-reliable-push
# about: Health checks and opt-in repair of native Discourse Web Push for installed PWAs.
# version: 0.1.1
# authors: discourse-reliable-push contributors
# required_version: 2.9.0

enabled_site_setting :reliable_push_enabled

register_asset "stylesheets/reliable-push.scss"

module ::DiscourseReliablePush
  PLUGIN_NAME = "discourse-reliable-push"
end

require_relative "lib/discourse_reliable_push/engine"

Discourse::Application.routes.append { mount ::DiscourseReliablePush::Engine, at: "/reliable-push" }
