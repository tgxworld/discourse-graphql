module DiscourseGraphQL
  module Chat
    class MessageUploadPageType < Types::BaseObject
      graphql_name "ChatMessageUploadPage"

      field :nodes, [Types::UploadType, null: true], null: false
      field :total_count, GraphQL::Types::BigInt, null: false
      field :page_info, Types::PageInfoType, null: false
    end
  end
end
