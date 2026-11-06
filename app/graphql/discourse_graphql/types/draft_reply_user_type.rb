module DiscourseGraphQL
  module Types
    class DraftReplyUserType < BaseObject
      field :id, GraphQL::Types::BigInt, null: true, hash_key: "id"
      field :username, String, null: true, hash_key: "username"
      field :name, String, null: true, hash_key: "name"
      field :avatar_template, String, null: true, hash_key: "avatar_template"
    end
  end
end
