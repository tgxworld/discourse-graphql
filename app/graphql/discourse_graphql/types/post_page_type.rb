module DiscourseGraphQL
  module Types
    class PostPageType < BaseObject
      field :nodes, [PostType], null: false
      field :page_info, PageInfoType, null: false
    end
  end
end
