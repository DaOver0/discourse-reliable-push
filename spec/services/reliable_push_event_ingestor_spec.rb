# frozen_string_literal: true

RSpec.describe ReliablePush::EventIngestor do
  fab!(:user)
  fab!(:topic)
  fab!(:post) { Fabricate(:post, topic: topic) }

  before do
    SiteSetting.reliable_push_enabled = true
    SiteSetting.reliable_push_post_notifications = true
    SiteSetting.reliable_push_respect_do_not_disturb = false
  end

  it "creates one durable delivery for a core post push" do
    payload = {
      notification_type: Notification.types[:mentioned],
      post_id: post.id,
      topic_id: topic.id,
      post_number: post.post_number,
      topic_title: topic.title,
      post_url: post.url,
      excerpt: "hello",
      username: post.user.username,
    }

    described_class.from_core_push(user:, payload:)
    described_class.from_core_push(user:, payload:)

    expect(ReliablePush::Delivery.count).to eq(1)
    expect(ReliablePush::Delivery.last.dedupe_key).to eq("post:mentioned:#{post.id}")
  end
end
