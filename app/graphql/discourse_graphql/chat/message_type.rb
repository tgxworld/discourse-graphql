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
      field :reactions, ReactionPageType, null: true do
        extras [:lookahead]
        argument :first, Integer, required: false, default_value: 30, replace_null_with_default: true
        argument :after, String, required: false
        complexity ->(_context, arguments, child) { 100 + arguments[:first].clamp(1, 50) * child }
      end

      def reactions(first:, lookahead:, after: nil)
        NativeArrayPage.call(source: object["reactions"], kind: "chat_message_reactions", context: context, lookahead: lookahead, first: first, after: after, maximum_first: 50, scope: object.slice("id", "chat_channel_id"))
      end
    end
  end
end
