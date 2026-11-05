module DiscourseGraphQL
  module Chat
    class ThreadUserType < Types::BaseObject
      graphql_name "ChatThreadUser"

      field :id, ID, null: true, hash_key: "id"
      field :username, String, null: true, hash_key: "username"
      field :name, String, null: true, hash_key: "name"
      field :avatar_template, String, null: true, hash_key: "avatar_template"
    end
  end
end
