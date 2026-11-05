module DiscourseGraphQL
  module Types
    class PageInfoType < BaseObject
      field :end_cursor, String, null: true
      field :has_next_page, Boolean, null: false
      field :start_cursor, String, null: true
      field :has_previous_page, Boolean, null: false

      def has_previous_page
        object.fetch(:has_previous_page, false)
      end
    end
  end
end
