module DiscourseGraphQL
  module Chat
    class BlockChangePageType < Types::BaseObject
      graphql_name "ChatBlockChangePage"

      field :nodes, [BlockChangeType, null: true], null: false
      field :total_count, GraphQL::Types::BigInt, null: false
      field :page_info, Types::PageInfoType, null: false
    end
  end
end
