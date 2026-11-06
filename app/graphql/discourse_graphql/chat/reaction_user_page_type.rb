module DiscourseGraphQL
  module Chat
    class ReactionUserPageType < Types::BaseObject
      graphql_name "ChatReactionUserPage"

      field :nodes, [ReactionUserType], null: false
      field :total_count, GraphQL::Types::BigInt, null: false
      field :page_info, Types::PageInfoType, null: false
    end
  end
end
