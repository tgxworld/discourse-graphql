module DiscourseGraphQL
  module Types
    class PostCreationPayloadType < BaseObject
      field :status, PostCreationStatus, null: false
      field :action, String, null: true
      field :post, PostType, null: true
      field :pending_count, Int, null: true
      field :errors, [UserErrorType], null: false

      def post
        return if object[:post_id].nil?

        dataloader.with(Loaders::RecordLoader, Post).load(object[:post_id])
      end
    end
  end
end
