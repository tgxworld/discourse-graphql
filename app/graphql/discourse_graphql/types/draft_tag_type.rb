module DiscourseGraphQL
  module Types
    class DraftTagType < BaseObject
      field :id, GraphQL::Types::BigInt, null: true, hash_key: "id"
      field :name, String, null: true, hash_key: "name"
      field :slug, String, null: true, hash_key: "slug"
      field :is_new, Boolean, null: true, hash_key: "isNew"
      field :format, DraftTagFormat, null: false, hash_key: "format"
    end
  end
end
