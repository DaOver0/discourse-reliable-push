# frozen_string_literal: true

RSpec.describe ReliablePush::AccessChecker do
  fab!(:author) { Fabricate(:user) }
  fab!(:user)
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, user: author, category: category) }
  fab!(:post) { Fabricate(:post, topic: topic, user: author) }

  before do
    SiteSetting.reliable_push_enabled = true
  end

  it "rejects an explicitly muted topic" do
    TopicUser.create!(
      user: user,
      topic: topic,
      notification_level: TopicUser.notification_levels[:muted],
    )

    expect(described_class.allowed_topic_post?(user: user, post: post)).to eq(false)
  end

  it "rejects a topic in a muted category" do
    CategoryUser.create!(
      user: user,
      category: category,
      notification_level: CategoryUser.notification_levels[:muted],
    )

    expect(described_class.allowed_topic_post?(user: user, post: post)).to eq(false)
  end

  it "rejects the author of the post" do
    expect(described_class.allowed_topic_post?(user: author, post: post)).to eq(false)
  end
end
