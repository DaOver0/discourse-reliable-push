# frozen_string_literal: true

RSpec.describe "Reliable Push subscriptions" do
  fab!(:user)
  fab!(:other_user, :user)

  let(:subscription_params) do
    {
      endpoint: "https://push.example.test/endpoint-12345678901234",
      keys: { p256dh: "B" * 87, auth: "a" * 22 },
    }
  end

  before do
    SiteSetting.reliable_push_enabled = true
    SiteSetting.reliable_push_test_notifications = true
    sign_in(user)
  end

  it "creates and verifies a subscription using core storage" do
    post "/reliable-push/sync.json", params: { subscription: subscription_params }
    expect(response.status).to eq(200)
    expect(response.parsed_body["registered"]).to eq(true)
    expect(user.push_subscriptions.count).to eq(1)

    post "/reliable-push/status.json", params: { subscription: subscription_params }
    expect(response.parsed_body["registered"]).to eq(true)
  end

  it "does not create duplicate records on repeated sync" do
    2.times do
      post "/reliable-push/sync.json", params: { subscription: subscription_params }
      expect(response.status).to eq(200)
    end
    expect(user.push_subscriptions.count).to eq(1)
  end

  it "rejects invalid endpoints" do
    post "/reliable-push/sync.json", params: {
      subscription: subscription_params.merge(endpoint: "http://localhost/internal"),
    }
    expect(response.status).not_to eq(200)
    expect(user.push_subscriptions.count).to eq(0)
  end

  it "transfers a shared browser subscription to the currently logged-in user" do
    PushSubscription.create!(user: other_user, data: subscription_params.to_json)
    post "/reliable-push/sync.json", params: { subscription: subscription_params }
    expect(response.status).to eq(200)
    expect(other_user.push_subscriptions.count).to eq(0)
    expect(user.push_subscriptions.count).to eq(1)
  end

  it "queues a test for the user's own device only" do
    post "/reliable-push/sync.json", params: { subscription: subscription_params }
    Jobs.expects(:enqueue).with(
      :reliable_push_test_notification,
      user_id: user.id,
      subscription_id: user.push_subscriptions.first.id,
    )
    post "/reliable-push/test.json", params: { subscription: subscription_params }
    expect(response.status).to eq(200)
    expect(response.parsed_body["queued"]).to eq(true)
    expect(response.parsed_body["delay_seconds"]).to eq(0)
  end

  it "schedules a push after PWA can be closed" do
    post "/reliable-push/sync.json", params: { subscription: subscription_params }
    Jobs.expects(:enqueue_in).with(
      30.seconds,
      :reliable_push_test_notification,
      user_id: user.id,
      subscription_id: user.push_subscriptions.first.id,
    )
    post "/reliable-push/test.json", params: { subscription: subscription_params, background: true }
    expect(response.status).to eq(200)
    expect(response.parsed_body).to include("queued" => true, "delay_seconds" => 30)
  end

  it "does not allow testing another user's subscription" do
    other = subscription_params.merge(endpoint: "https://push.example.test/other-12345678901234")
    PushSubscription.create!(user: other_user, data: other.to_json)
    post "/reliable-push/test.json", params: { subscription: other }
    expect(response.status).not_to eq(200)
  end
end
