module DiscourseGraphQL
  module Types
    class BookmarkPageType < BaseObject
      field :nodes, [BookmarkType], null: false
      field :page_info, PageInfoType, null: false
    end
  end
end
