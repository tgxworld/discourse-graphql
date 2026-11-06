module DiscourseGraphQL
  module Chat
    class ReactionUserType < ReactionActorType
      graphql_name "ChatReactionUser"

      field :reaction, String, null: true
    end
  end
end
