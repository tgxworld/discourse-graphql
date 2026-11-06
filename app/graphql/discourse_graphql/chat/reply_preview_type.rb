module DiscourseGraphQL
  module Chat
    class ReplyPreviewType < Types::BaseObject
      graphql_name "ChatReplyPreview"

      field :id, ID, null: true, hash_key: "id"
      field :cooked, String, null: true, hash_key: "cooked"
      field :excerpt, String, null: true, hash_key: "excerpt"
      field :user, Types::UserSnapshotType, null: true, hash_key: "user"
      field :webhook, WebhookPresentationType, null: true, hash_key: "chat_webhook_event"
    end
  end
end
