module DiscourseGraphQL
  module Chat
    class MessageAuthorType < Types::BaseObject
      graphql_name "ChatMessageAuthor"

      field :id, ID, null: true
      field :username, String, null: false
      field :name, String, null: true
      field :avatar_template, String, null: false, hash_key: "avatar_template"
    end
  end
end
