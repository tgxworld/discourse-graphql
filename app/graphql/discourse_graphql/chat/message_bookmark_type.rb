module DiscourseGraphQL
  module Chat
    class MessageBookmarkType < Types::BaseObject
      graphql_name "ChatMessageBookmark"

      field :id, ID, null: true, hash_key: "id"
      field :name, String, null: true, hash_key: "name"
      field :reminder_at, Types::NativeTimestamp, null: true, hash_key: "reminder_at"
      field :auto_delete_preference, Types::BookmarkAutoDeletePreference, null: true, hash_key: "auto_delete_preference"
      field :target_id, ID, null: true, hash_key: "bookmarkable_id"
      field :target_type, String, null: true, hash_key: "bookmarkable_type"
    end
  end
end
