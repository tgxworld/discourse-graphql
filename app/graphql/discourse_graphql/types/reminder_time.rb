module DiscourseGraphQL
  module Types
    class ReminderTime < GraphQL::Types::ISO8601DateTime
      graphql_name "ReminderTime"
      self.time_precision = ActiveSupport::JSON::Encoding.time_precision
    end
  end
end
