module DiscourseGraphQL
  module Chat
    class ThreadNotificationLevel < Types::BaseEnum
      graphql_name "ChatThreadNotificationLevel"

      ::Chat::UserChatThreadMembership.notification_levels.each do |level, number|
        value level.upcase, value: number
      end
    end
  end
end
