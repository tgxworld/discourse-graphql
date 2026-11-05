module DiscourseGraphQL
  module Chat
    class MessagePageType < Types::BaseObject
      graphql_name "ChatMessagePage"

      field :nodes, [MessageType], null: false
      field :page_info, Types::PageInfoType, null: false
    end
  end
end
