# frozen_string_literal: true

RSpec.describe ReliablePush::AccessChecker do
  fab!(:user)
  fab!(:topic)
  fab!(:post) { Fabricate(:post, topic: topic) }

  before do
    SiteSetting.reliable_push_enabled = true
    SiteSetting.reliable_push_respect_do_not_disturb = false
  end

  it "rejects a delivery when the user muted its topic" do
    TopicUser.change(
      user.id,
      topic.id,
      notification_level: TopicUser.notification_levels[:muted],
    )

    delivery = ReliablePush::Delivery.create!(
      user: user,
      kind: "broadcast_topic_post",
      dedupe_key: "post:#{post.id}",
      payload: {
        post_id: post.id,
        topic_id: topic.id,
        post_number: post.post_number,
        title: "title",
        body: "body",
        url: post.url,
      },
      priority: 25,
      expires_at: 1.hour.from_now,
    )

    expect(described_class.allowed?(delivery)).to eq(false)
  end
end
