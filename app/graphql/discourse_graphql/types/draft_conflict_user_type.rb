module DiscourseGraphQL
  module Types
    class DraftConflictUserType < BaseObject
      field :id, ID, null: false, hash_key: "id"
      field :username, String, null: false, hash_key: "username"
      field :name, String, null: true, hash_key: "name"
      field :avatar_template, String, null: true, hash_key: "avatar_template"
    end
  end
end
