module DiscourseGraphQL
  module Types
    class BookmarkAutoDeletePreference < BaseEnum
      ::Bookmark.auto_delete_preferences.each { |name, level| value name.to_s.upcase, value: level }
    end
  end
end
