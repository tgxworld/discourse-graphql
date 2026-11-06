module DiscourseGraphQL
  module Chat
    class MessageBlockPageType < Types::BaseObject
      graphql_name "ChatMessageBlockPage"

      field :nodes, [MessageBlockType, null: true], null: false
      field :total_count, GraphQL::Types::BigInt, null: false
      field :page_info, Types::PageInfoType, null: false
    end
  end
end
