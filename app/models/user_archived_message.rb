class UserArchivedMessage < ActiveRecord::Base
  belongs_to :user
  belongs_to :topic

  def self.move_to_inbox!(user_id, topic_id)
    return if (TopicUser.where(
      user_id: user_id,
      topic_id: topic_id,
      notification_level: TopicUser.notification_levels[:muted]
    ).exists?)

    UserArchivedMessage.where(user_id: user_id, topic_id: topic_id).destroy_all
    trigger(:move_to_inbox, user_id, topic_id)
    MessageBus.publish("/topic/#{topic_id}", {type: "move_to_inbox"}, user_ids: [user_id])
  end

  def self.archive!(user_id, topic_id)
    UserArchivedMessage.where(user_id: user_id, topic_id: topic_id).destroy_all
    UserArchivedMessage.create!(user_id: user_id, topic_id: topic_id)
    trigger(:archive_message, user_id, topic_id)
    MessageBus.publish("/topic/#{topic_id}", {type: "archived"}, user_ids: [user_id])
  end

  def self.trigger(event, user_id, topic_id)
    user = User.find_by(id: user_id)
    topic = Topic.find_by(id: topic_id)
    if user && topic
      DiscourseEvent.trigger(event, {user: user, topic: topic})
    end
  end
end

# == Schema Information
#
# Table name: user_archived_messages
#
#  id         :integer          not null, primary key
#  user_id    :integer          not null
#  topic_id   :integer          not null
#  created_at :datetime
#  updated_at :datetime
#
# Indexes
#
#  index_user_archived_messages_on_user_id_and_topic_id  (user_id,topic_id) UNIQUE
#
