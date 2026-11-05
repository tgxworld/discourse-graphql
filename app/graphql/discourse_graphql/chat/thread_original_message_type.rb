module DiscourseGraphQL
  module Chat
    class ThreadOriginalMessageType < Types::BaseObject
      graphql_name "ChatThreadOriginalMessage"

      field :id, ID, null: true, hash_key: "id"
      field :raw, String, null: true, hash_key: "message"
      field :cooked, String, null: true, hash_key: "cooked"
      field :created_at, Types::NativeTimestamp, null: true, hash_key: "created_at"
      field :excerpt, String, null: true, hash_key: "excerpt"
      field :channel_id, ID, null: true, hash_key: "chat_channel_id"
      field :deleted_at, Types::NativeTimestamp, null: true, hash_key: "deleted_at"
      field :author, ThreadUserType, null: true, hash_key: "user"
      field :mentioned_users, ThreadUserPageType, null: true do
        extras [:lookahead]
        argument :first,
                 Integer,
                 required: false,
                 default_value: 25,
                 replace_null_with_default: true
        argument :after, String, required: false
        complexity ->(_context, arguments, child) { 100 + arguments[:first].clamp(1, 50) * child }
      end

      def mentioned_users(first:, lookahead:, after: nil)
        NativeArrayPage.call(
          source: object["mentioned_users"],
          kind: "chat_thread_mentions",
          context: context,
          lookahead: lookahead,
          first: first,
          after: after,
          maximum_first: 50,
          scope: object.slice("id", "chat_channel_id"),
        )
      end
    end
  end
end
