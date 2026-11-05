module DiscourseGraphQL
  module Chat
    class ReactionType < Types::BaseObject
      graphql_name "ChatReaction"

      field :emoji, String, null: false
      field :count, GraphQL::Types::BigInt, null: false
      field :reacted, Boolean, null: false
      field :users, [ReactionActorType, null: true], null: false do
        complexity ->(_context, _arguments, child) { 1 + 5 * child }
      end
    end
  end
end
