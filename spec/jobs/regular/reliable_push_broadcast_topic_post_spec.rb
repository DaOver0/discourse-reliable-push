# frozen_string_literal: true

RSpec.describe Jobs::ReliablePushBroadcastTopicPost do
  fab!(:author) { Fabricate(:user) }
  fab!(:recipient) { Fabricate(:user) }
  fab!(:muted_user) { Fabricate(:user) }
  fab!(:topic) { Fabricate(:topic, user: author) }
  fab!(:post) { Fabricate(:post, topic: topic, user: author) }

  before do
    SiteSetting.reliable_push_enabled = true
    SiteSetting.reliable_push_post_notifications = true
    SiteSetting.reliable_push_topic_events_enabled = true
    SiteSetting.reliable_push_topic_posts_enabled = true
    SiteSetting.reliable_push_new_topics_enabled = true
    SiteSetting.reliable_push_max_fanout = 100

    ReliablePush::Subscription.sync!(
      user: recipient,
      subscription: {
        endpoint: "https://push.test/recipient",
        keys: { p256dh: "recipient-key", auth: "recipient-auth" },
      },
    )
    ReliablePush::Subscription.sync!(
      user: muted_user,
      subscription: {
        endpoint: "https://push.test/muted",
        keys: { p256dh: "muted-key", auth: "muted-auth" },
      },
    )
    TopicUser.create!(
      user: muted_user,
      topic: topic,
      notification_level: TopicUser.notification_levels[:muted],
    )

    allow(Jobs).to receive(:enqueue)
    allow(MessageBus).to receive(:publish)
  end

  it "creates a delivery for an eligible subscribed user and excludes muted users" do
    described_class.new.execute(post_id: post.id)

    expect(ReliablePush::Delivery.where(user: recipient, source_type: "Post", source_id: post.id)).to exist
    expect(ReliablePush::Delivery.where(user: muted_user, source_type: "Post", source_id: post.id)).not_to exist
    expect(ReliablePush::Delivery.where(user: author, source_type: "Post", source_id: post.id)).not_to exist
  end
end
