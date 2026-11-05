module DiscourseGraphQL
  module Chat
    class ThreadBusPositionType < Types::BaseObject
      graphql_name "ChatThreadBusPosition"

      field :thread_message_bus_last_id, GraphQL::Types::BigInt, null: true, hash_key: "thread_message_bus_last_id"
    end
  end
end
