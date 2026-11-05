module DiscourseGraphQL
  module Types
    class PageInfoType < BaseObject
      field :end_cursor, String, null: true
      field :has_next_page, Boolean, null: false
    end
  end
end
