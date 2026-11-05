module DiscourseGraphQL
  module Chat
    class MessageType < Types::BaseObject
      graphql_name "ChatMessage"

      field :id, ID, null: false
      field :raw, String, null: true, hash_key: "message"
      field :cooked, String, null: true
      field :excerpt, String, null: true
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false, hash_key: "created_at"
      field :deleted_at, GraphQL::Types::ISO8601DateTime, null: true, hash_key: "deleted_at"
      field :deleted_by_id, ID, null: true, hash_key: "deleted_by_id"
      field :author, MessageAuthorType, null: true, hash_key: "user"
      field :thread_id, ID, null: true, hash_key: "thread_id"
      field :channel_id, ID, null: false, hash_key: "chat_channel_id"
      field :streaming, Boolean, null: false
    end
  end
end
