module DiscourseGraphQL
  module Chat
    class ThreadTrackingType < Types::BaseObject
      graphql_name "ChatThreadTracking"

      field :thread_id, ID, null: true, hash_key: "thread_id"
      field :channel_id, ID, null: true, hash_key: "channel_id"
      field :mention_count, GraphQL::Types::BigInt, null: true, hash_key: "mention_count"
      field :unread_count, GraphQL::Types::BigInt, null: true, hash_key: "unread_count"
      field :watched_threads_unread_count,
            GraphQL::Types::BigInt,
            null: true,
            hash_key: "watched_threads_unread_count"
    end
  end
end
