module DiscourseGraphQL
  module Chat
    class BlockElementPageType < Types::BaseObject
      graphql_name "ChatBlockElementPage"

      field :nodes, [BlockElementType, null: true], null: false
      field :total_count, GraphQL::Types::BigInt, null: false
      field :page_info, Types::PageInfoType, null: false
    end
  end
end
