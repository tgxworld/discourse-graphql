module DiscourseGraphQL
  module Chat
    class NotificationLevel < Types::BaseEnum
      graphql_name "ChatChannelNotificationLevel"

      ::Chat::UserChatChannelMembership.notification_levels.each_key do |level|
        value level.upcase, value: level
      end
    end
  end
end
