module DiscourseGraphQL
  module Types
    class DraftType < BaseObject
      field :key, String, null: false, hash_key: "draft_key"
      field :sequence, GraphQL::Types::BigInt, null: false, hash_key: "sequence"
      field :content, DraftContentType, null: true, hash_key: "data"
      field :title, String, null: true, hash_key: "title"
      field :slug, String, null: true, hash_key: "slug"
      field :category_id, ID, null: true, hash_key: "category_id"
      field :topic_id, ID, null: true, hash_key: "topic_id"
      field :display_username, String, null: true, hash_key: "username"
      field :display_name, String, null: true, hash_key: "name"
      field :draft_username, String, null: true, hash_key: "draft_username"
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false, hash_key: "created_at"
    end
  end
end
