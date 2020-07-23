module Types
  class SearchTopicType < Types::BaseObject
    description "SearchTopicType"

    field :id, ID, null: false
    field :fancy_title, String, null: false
    field :slug, String, null: false
    field :posts_count, Int, null: false
    field :archetype, String, null: false
    field :pinned, Boolean, null: false
    field :unpinned, Boolean, null: false
    field :visible, Boolean, null: false
    field :closed, Boolean, null: false
    field :archived, Boolean, null: false
    field :liked, Boolean, null: false
    field :category_id, Int, null: false

    def liked
      object.user_data&.liked
    end

    def pinned
      PinnedCheck.pinned?(object, object.user_data)
    end

    def unpinned
      PinnedCheck.unpinned?(object, object.user_data)
    end
  end
end
