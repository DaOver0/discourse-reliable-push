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
    SiteSetting.reliable_push_notify_all_topic_posts = true
    SiteSetting.reliable_push_respect_do_not_disturb = false

    [recipient, muted_user].each_with_index do |user, index|
      ReliablePush::Subscription.create!(
        user: user,
        endpoint_digest: Digest::SHA256.hexdigest("https://push.example/#{index}"),
        endpoint: "https://push.example/#{index}",
        p256dh: "p256dh-#{index}",
        auth: "auth-#{index}",
      )
    end

    TopicUser.change(
      muted_user.id,
      topic.id,
      notification_level: TopicUser.notification_levels[:muted],
    )
  end

  it "fans out to subscribed users but skips the author and topic-muted users" do
    described_class.new.execute(post_id: post.id)

    expect(ReliablePush::Delivery.where(user: recipient, source_type: "Post", source_id: post.id).exists?).to eq(true)
    expect(ReliablePush::Delivery.where(user: muted_user, source_type: "Post", source_id: post.id).exists?).to eq(false)
    expect(ReliablePush::Delivery.where(user: author, source_type: "Post", source_id: post.id).exists?).to eq(false)
  end
end
