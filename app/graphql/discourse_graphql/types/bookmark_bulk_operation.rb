module DiscourseGraphQL
  module Types
    class BookmarkBulkOperation < BaseEnum
      value "CLEAR_REMINDER", value: "clear_reminder"
      value "DELETE", value: "delete"
    end
  end
end
