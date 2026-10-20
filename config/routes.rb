# frozen_string_literal: true

DiscourseReliablePush::Engine.routes.draw do
  defaults format: :json do
    post "/status" => "subscriptions#status"
    post "/sync" => "subscriptions#sync"
    post "/test" => "subscriptions#test"
  end
end
