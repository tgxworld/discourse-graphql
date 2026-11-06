module DiscourseGraphQL
  module Types
    class PostType < Types::BaseObject
      description "Post"

      field :id, ID, null: false
      field :name, String, null: true
      field :username, String, null: true
      field :avatar_template, String, null: true
      field :like_count, Int, null: false
      field :post_number, Int, null: false
      field :created_at, String, null: false
      field :updated_at, String, null: true
      field :cooked, String, null: false
      field :raw, String, null: true
      field :author, UserType, null: true
      field :reply_to_post_number, Int, null: true
      field :topic, TopicType, null: false

      def self.authorized?(object, context)
        super && context[:guardian].can_see_post?(object)
      end

      def name
        serializer.name if serializer.include_name?
      end

      def username
        serializer.username
      end

      def avatar_template
        serializer.avatar_template
      end

      def cooked
        serializer.cooked
      end

      def raw
        serializer.raw if serializer.include_raw?
      end

      def updated_at
        PostSerializer
          .new(object, scope: context[:guardian], root: false, only: [:updated_at])
          .as_json
          .as_json[
          "updated_at"
        ]
      end

      def author
        return object.user if object.association(:user).loaded?

        dataloader.with(Loaders::RecordLoader, User).load(object.user_id)
      end

      def topic
        return object.topic if object.association(:topic).loaded?

        dataloader.with(Loaders::RecordLoader, Topic).load(object.topic_id)
      end

      private

      def serializer
        @serializer ||=
          PostSerializer.new(object, scope: context[:guardian], root: false, add_raw: true)
      end
    end
  end
end
