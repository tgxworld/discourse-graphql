module DiscourseGraphQL
  module Types
    class UserSnapshotType < BaseObject
      graphql_name "UserSnapshot"

      field :id, ID, null: true, hash_key: "id"
      field :username, String, null: true, hash_key: "username"
      field :name, String, null: true, hash_key: "name"
      field :avatar_template, String, null: true, hash_key: "avatar_template"
      field :status, UserStatusType, null: true, hash_key: "status"
    end
  end
end
