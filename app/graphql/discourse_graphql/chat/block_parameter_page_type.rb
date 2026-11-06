module DiscourseGraphQL
  module Chat
    class BlockParameterPageType < Types::BaseObject
      graphql_name "ChatBlockParameterPage"

      field :nodes, [BlockParameterType, null: true], null: false
      field :total_count, GraphQL::Types::BigInt, null: false
      field :page_info, Types::PageInfoType, null: false
    end
  end
end
