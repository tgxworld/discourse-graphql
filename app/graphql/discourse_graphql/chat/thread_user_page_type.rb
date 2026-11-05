module DiscourseGraphQL
  module Chat
    class ThreadUserPageType < Types::BaseObject
      graphql_name "ChatThreadUserPage"

      field :nodes, [ThreadUserType, null: true], null: false
      field :total_count, GraphQL::Types::BigInt, null: false
      field :page_info, Types::PageInfoType, null: false
    end
  end
end
