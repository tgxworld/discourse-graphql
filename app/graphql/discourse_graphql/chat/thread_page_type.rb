module DiscourseGraphQL
  module Chat
    class ThreadPageType < Types::BaseObject
      graphql_name "ChatThreadPage"

      field :nodes, [ThreadType], null: true
      field :tracking, [ThreadTrackingType], null: true
      field :page_info, Types::PageInfoType, null: true
    end
  end
end
