module DiscourseGraphQL
  module Chat
    class MessagePageType < Types::BaseObject
      graphql_name "ChatMessagePage"

      field :nodes, [MessageType], null: true
      field :page_info, Types::PageInfoType, null: true
    end
  end
end
