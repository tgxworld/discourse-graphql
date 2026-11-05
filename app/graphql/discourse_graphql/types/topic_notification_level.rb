module DiscourseGraphQL
  module Types
    class TopicNotificationLevel < BaseEnum
      ::TopicUser.notification_levels.to_a.uniq { |_name, level| level }.each do |name, level|
        value name.to_s.upcase, value: level
      end
    end
  end
end
