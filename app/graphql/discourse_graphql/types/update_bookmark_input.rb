module DiscourseGraphQL
  module Types
    class UpdateBookmarkInput < BaseInputObject
      argument :id, ID, required: true
      argument :name, String, required: :nullable
      argument :reminder_at, ReminderTime, required: :nullable
      argument :auto_delete_preference, BookmarkAutoDeletePreference, required: :nullable
    end
  end
end
