module DiscourseGraphQL
  module Chat
    class ThreadMessagePageType < Types::BaseObject
      graphql_name "ChatThreadMessagePage"

      field :nodes, [MessageType], null: true
      field :page_info, Types::PageInfoType, null: true
    end
  end
end
