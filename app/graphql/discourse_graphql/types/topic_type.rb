module DiscourseGraphQL
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
      field :category, CategoryType, null: true
      field :author, UserType, null: true
      field :current_user_state, TopicStateType, null: true

      def self.authorized?(object, context)
        super &&
          context
            .dataloader
            .with(Loaders::TopicAuthorization, guardian: context[:guardian])
            .load(object.id)
      end

      def current_user_state
        dataloader.with(Loaders::TopicState, user: context[:guardian].user).load(object)
      end

      def author
        dataloader.with(Loaders::RecordLoader, User).load(object.user_id)
      end

      def category
        return object.category if object.association(:category).loaded?

        dataloader.with(Loaders::RecordLoader, Category).load(object.category_id)
      end
    end
  end
end
