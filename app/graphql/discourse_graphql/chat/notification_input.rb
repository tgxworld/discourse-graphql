module DiscourseGraphQL
  module Chat
    class NotificationInput < Types::BaseInputObject
      graphql_name "ChatNotificationInput"

      argument :channel_id, ID, required: true
      argument :muted, Boolean, required: false
      argument :notification_level, NotificationLevel, required: false
    end
  end
end
