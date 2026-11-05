module DiscourseGraphQL
  module Chat
    class ThreadPreviewType < Types::BaseObject
      graphql_name "ChatThreadPreview"

      field :last_reply_created_at, GraphQL::Types::ISO8601DateTime, null: true, hash_key: "last_reply_created_at"
      field :last_reply_excerpt, String, null: true, hash_key: "last_reply_excerpt"
      field :last_reply_id, ID, null: true, hash_key: "last_reply_id"
      field :participant_count, GraphQL::Types::BigInt, null: true, hash_key: "participant_count"
      field :reply_count, GraphQL::Types::BigInt, null: true, hash_key: "reply_count"
      field :last_reply_user, ThreadUserType, null: true, hash_key: "last_reply_user"
      field :participant_users, [ThreadUserType, null: true], null: true, hash_key: "participant_users" do
        complexity ->(_context, _arguments, child) { 1 + 10 * child }
      end
    end
  end
end
