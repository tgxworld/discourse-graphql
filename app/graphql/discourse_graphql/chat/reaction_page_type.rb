module DiscourseGraphQL
  module Chat
    class ReactionPageType < Types::BaseObject
      graphql_name "ChatReactionPage"

      field :nodes, [ReactionType], null: false
      field :total_count, Integer, null: false
      field :page_info, Types::PageInfoType, null: false
    end
  end
end
