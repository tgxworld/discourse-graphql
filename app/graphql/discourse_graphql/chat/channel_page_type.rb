module DiscourseGraphQL
  module Chat
    class ChannelPageType < Types::BaseObject
      graphql_name "ChatChannelPage"

      field :nodes, [ChannelType], null: false
      field :page_info, Types::PageInfoType, null: false
    end
  end
end
