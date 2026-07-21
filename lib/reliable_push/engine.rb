# frozen_string_literal: true

module ::ReliablePush
  class Engine < ::Rails::Engine
    engine_name "reliable_push"
    isolate_namespace ReliablePush
  end
end

ReliablePush::Engine.routes.draw do
  get "/status" => "status#show"
  get "/preferences" => "preferences#show"
  put "/preferences" => "preferences#update"
  patch "/preferences" => "preferences#update"
  post "/subscriptions/sync" => "subscriptions#sync"
  post "/ack/received" => "acknowledgements#received"
  post "/ack/opened" => "acknowledgements#opened"

  # Compatibility with 0.2.x notification payloads that embedded the token in
  # the acknowledgement URL.
  post "/ack/:delivery_id/:token/received" => "acknowledgements#received"
  post "/ack/:delivery_id/:token/opened" => "acknowledgements#opened"

  namespace :admin do
    get "/status" => "status#show"
  end
end
