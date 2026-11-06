module DiscourseGraphQL
  module Types
    class UserStatusType < BaseObject
      graphql_name "UserStatusSnapshot"

      field :description, String, null: true, hash_key: "description"
      field :emoji, String, null: true, hash_key: "emoji"
      field :ends_at, NativeTimestamp, null: true, hash_key: "ends_at"
      field :message_bus_last_id,
            GraphQL::Types::BigInt,
            null: true,
            hash_key: "message_bus_last_id"
    end
  end
end
