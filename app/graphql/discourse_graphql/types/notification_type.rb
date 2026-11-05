module DiscourseGraphQL
  module Types
    class NotificationType < BaseObject
      field :id, ID, null: false, hash_key: "id"
      field :notification_type, Int, null: false, hash_key: "notification_type"
      field :read, Boolean, null: false, hash_key: "read"
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false, hash_key: "created_at"
      field :topic_id, ID, null: true, hash_key: "topic_id"
      field :post_number, Int, null: true, hash_key: "post_number"
      field :fancy_title, String, null: true, hash_key: "fancy_title"
      field :slug, String, null: true, hash_key: "slug"
      field :acting_user_name, String, null: true, hash_key: "acting_user_name"
      field :acting_user_avatar_template, String, null: true, hash_key: "acting_user_avatar_template"
    end
  end
end
