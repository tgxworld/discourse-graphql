module DiscourseGraphQL
  module Types
    class DraftPageType < BaseObject
      field :nodes, [DraftType], null: false
      field :page_info, PageInfoType, null: false
    end
  end
end
