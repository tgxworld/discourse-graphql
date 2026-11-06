module DiscourseGraphQL
  module Chat
    class MessageUserPageType < Types::BaseObject
      graphql_name "ChatMessageUserPage"

      field :nodes, [Types::UserSnapshotType, null: true], null: false
      field :total_count, GraphQL::Types::BigInt, null: false
      field :page_info, Types::PageInfoType, null: false
    end
  end
end
