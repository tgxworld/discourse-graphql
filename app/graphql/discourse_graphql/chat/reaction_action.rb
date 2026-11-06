module DiscourseGraphQL
  module Chat
    class ReactionAction < Types::BaseEnum
      graphql_name "ChatReactionAction"

      value "ADD", value: ::Chat::MessageReactor::ADD_REACTION
      value "REMOVE", value: ::Chat::MessageReactor::REMOVE_REACTION
    end
  end
end
