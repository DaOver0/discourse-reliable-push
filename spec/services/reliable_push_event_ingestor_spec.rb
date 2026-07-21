# frozen_string_literal: true

RSpec.describe ReliablePush::EventIngestor do
  fab!(:author) { Fabricate(:user) }
  fab!(:user)
  fab!(:topic) { Fabricate(:topic, user: author) }
  fab!(:post) { Fabricate(:post, topic: topic, user: author) }

  before do
    SiteSetting.reliable_push_enabled = true
    SiteSetting.reliable_push_post_notifications = true
    SiteSetting.reliable_push_topic_events_enabled = true
    SiteSetting.reliable_push_topic_posts_enabled = true
    SiteSetting.reliable_push_mentions_replies_enabled = true

    allow(Jobs).to receive(:enqueue)
    allow(MessageBus).to receive(:publish)
  end

  it "deduplicates repeated core push payloads for the same post" do
    payload = {
      notification_type: Notification.types[:replied],
      post_id: post.id,
      topic_id: topic.id,
      post_number: post.post_number,
      translated_title: "Reply",
      excerpt: "A reply",
      post_url: post.url,
    }

    first = described_class.from_core_push(user: user, payload: payload)
    second = described_class.from_core_push(user: user, payload: payload)

    expect(first).to be_handled
    expect(second).to be_handled
    expect(ReliablePush::Delivery.where(user: user, dedupe_key: "post:#{post.id}").count).to eq(1)
    expect(MessageBus).to have_received(:publish).once
  end

  it "upgrades a generic topic broadcast to a personal mention without a duplicate" do
    broadcast = described_class.topic_post(user: user, post: post)
    mention =
      described_class.from_core_push(
        user: user,
        payload: {
          notification_type: Notification.types[:mentioned],
          post_id: post.id,
          topic_id: topic.id,
          post_number: post.post_number,
          translated_title: "Mention",
          excerpt: "You were mentioned",
          post_url: post.url,
        },
      )

    expect(broadcast).to be_handled
    expect(mention).to be_handled

    delivery = ReliablePush::Delivery.find_by!(user: user, dedupe_key: "post:#{post.id}")
    expect(delivery.kind).to eq("mentioned")
    expect(delivery.priority).to eq(110)
    expect(ReliablePush::Delivery.where(user: user, dedupe_key: "post:#{post.id}").count).to eq(1)
  end

  it "uses notification data metadata to deduplicate persisted notifications" do
    described_class.topic_post(user: user, post: post)

    notification =
      Notification.create!(
        user: user,
        notification_type: Notification.types[:mentioned],
        topic_id: topic.id,
        post_number: post.post_number,
        data: {
          post_id: post.id,
          post_number: post.post_number,
          topic_title: topic.title,
          display_username: author.username,
        }.to_json,
      )

    result = described_class.from_notification(notification)

    expect(result).to be_handled
    delivery = ReliablePush::Delivery.find_by!(user: user, dedupe_key: "post:#{post.id}")
    expect(delivery.kind).to eq("mentioned")
    expect(ReliablePush::Delivery.where(user: user, dedupe_key: "post:#{post.id}").count).to eq(1)
  end
end
