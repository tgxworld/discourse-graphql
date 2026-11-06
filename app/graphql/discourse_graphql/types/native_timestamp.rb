module DiscourseGraphQL
  module Types
    class NativeTimestamp < GraphQL::Types::ISO8601DateTime
      graphql_name "NativeTimestamp"
      self.time_precision = ActiveSupport::JSON::Encoding.time_precision
    end
  end
end
