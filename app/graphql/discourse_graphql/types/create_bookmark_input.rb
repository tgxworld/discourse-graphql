module DiscourseGraphQL
  module Types
    class CreateBookmarkInput < BaseInputObject
      argument :target_id, ID, required: true
      argument :target_type, BookmarkTarget, required: true
      argument :name, String, required: false
      argument :reminder_at, ReminderTime, required: false
      argument :auto_delete_preference, BookmarkAutoDeletePreference, required: false
    end
  end
end
