# frozen_string_literal: true

module ::ReliablePush
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace ReliablePush
  end
end

ReliablePush::Engine.routes.draw do
  post "/subscriptions/sync" => "subscriptions#sync"
  get "/status" => "status#show"
  get "/admin/status" => "admin/status#show"
  post "/ack/:delivery_id/:token/received" => "acknowledgements#received"
  post "/ack/:delivery_id/:token/opened" => "acknowledgements#opened"
end

Discourse::Application.routes.draw { mount ::ReliablePush::Engine, at: "/reliable-push" }
