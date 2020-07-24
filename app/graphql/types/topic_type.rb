module Types
  class TopicType < Types::BaseObject
    description "Topic"

    field :id, ID, null: false
    field :fancy_title, String, null: false
    field :slug, String, null: false
    field :posts_count, Int, null: false
    field :archetype, String, null: false
    field :visible, Boolean, null: false
    field :closed, Boolean, null: false
    field :archived, Boolean, null: false
    field :views, Int, null: false
    field :reply_count, Int, null: false
  end
end
