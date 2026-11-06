module DiscourseGraphQL
  module Types
    class BookmarkPayloadType < BaseObject
      field :success, Boolean, null: false
      field :id, ID, null: true
      field :changed_ids, [ID], null: true
      field :topic_bookmarked, Boolean, null: true
      field :errors, [UserErrorType], null: false
    end
  end
end
