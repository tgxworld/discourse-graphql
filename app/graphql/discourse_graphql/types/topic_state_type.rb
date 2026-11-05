module DiscourseGraphQL
  module Types
    class TopicStateType < BaseObject
      field :last_read_post_number, Int, null: true
      field :notification_level, TopicNotificationLevel, null: false
      field :total_time_viewed_ms, Int, null: false, method: :total_msecs_viewed
    end
  end
end
