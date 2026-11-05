module DiscourseGraphQL
  module Chat
    class ReactionActorType < Types::BaseObject
      graphql_name "ChatReactionActor"

      field :id, ID, null: true
      field :username, String, null: true
      field :name, String, null: true
      field :avatar_template, String, null: true, hash_key: "avatar_template"
    end
  end
end
