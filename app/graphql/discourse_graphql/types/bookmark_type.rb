module DiscourseGraphQL
  module Types
    class BookmarkType < BaseObject
      field :id, ID, null: false, hash_key: "id"
      field :name, String, null: true, hash_key: "name"
      field :reminder_at, ReminderTime, null: true, hash_key: "reminder_at"
      field :auto_delete_preference,
            BookmarkAutoDeletePreference,
            null: true,
            hash_key: "auto_delete_preference"
      field :pinned, Boolean, null: true, hash_key: "pinned"
      field :title, String, null: true, hash_key: "title"
      field :fancy_title, String, null: true, hash_key: "fancy_title"
      field :excerpt, String, null: true, hash_key: "excerpt"
      field :target_id, ID, null: false, hash_key: "bookmarkable_id"
      field :target_type, String, null: false, hash_key: "bookmarkable_type"
      field :target_url, String, null: true, hash_key: "bookmarkable_url"
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false, hash_key: "created_at"
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false, hash_key: "updated_at"
    end
  end
end
