module DiscourseGraphQL
  module Types
    class MutationType < Types::BaseObject
      Extensions.mutation_modules.each { |extension| include extension }

      field :mark_notification_read, ActionPayloadType, null: true, complexity: 1000 do
        argument :id, ID, required: true
      end
      field :mark_all_notifications_read, ActionPayloadType, null: true, complexity: 4000

      field :create_topic, PostCreationPayloadType, null: false, complexity: 1000 do
        argument :input, CreateTopicInput, required: true
      end

      field :create_post, PostCreationPayloadType, null: false, complexity: 1000 do
        argument :input, CreatePostInput, required: true
      end

      def mark_notification_read(id:)
        mark_notifications(id: id)
      end

      def mark_all_notifications_read
        mark_notifications
      end

      def create_topic(input:)
        parameters = input.to_h
        parameters[:category] = parameters.delete(:category_id) if parameters.key?(:category_id)
        create(parameters: parameters)
      end

      def create_post(input:)
        create(parameters: input.to_h)
      end

      private

      def mark_notifications(id: nil)
        context.dataloader.clear_cache
        NotificationReading.new(request: context[:request], request_method: "PUT").call(id: id)
      ensure
        context.dataloader.clear_cache
      end

      def create(parameters:)
        context.dataloader.clear_cache
        result = PostCreation.new(request: context[:request]).call(parameters: parameters)
        context.dataloader.clear_cache
        result
      end
    end
  end
end
