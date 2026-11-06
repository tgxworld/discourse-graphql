module DiscourseGraphQL
  module Chat
    class ThreadType < Types::BaseObject
      graphql_name "ChatThread"

      field :id, ID, null: true, hash_key: "id"
      field :title, String, null: true, hash_key: "title"
      field :status, ThreadStatus, null: true, hash_key: "status"
      field :channel_id, ID, null: true, hash_key: "channel_id"
      field :reply_count, GraphQL::Types::BigInt, null: true, hash_key: "reply_count"
      field :last_message_id, ID, null: true, hash_key: "last_message_id"
      field :force, Boolean, null: true, hash_key: "force"
      field :original_message, ThreadOriginalMessageType, null: true, hash_key: "original_message"
      field :preview, ThreadPreviewType, null: true, hash_key: "preview"
      field :current_user_membership,
            ThreadMembershipType,
            null: true,
            hash_key: "current_user_membership"
      field :meta, ThreadMetaType, null: true, hash_key: "meta"
    end
  end
end
