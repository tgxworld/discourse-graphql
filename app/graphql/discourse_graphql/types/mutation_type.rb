module DiscourseGraphQL
  module Types
    class MutationType < Types::BaseObject
      include TopicStateMutationFields
      include BookmarkMutationFields
      include DraftMutationFields
      Extensions.mutation_modules.each { |extension| include extension }

      field :create_upload, UploadPayloadType, null: true, complexity: 1000 do
        argument :input, CreateUploadInput, required: true
      end

      def create_upload(input:)
        parameters = input.to_h
        if parameters[:file].present? == parameters[:url].present? || parameters[:url]&.bytesize.to_i > 4096
          raise Discourse::InvalidParameters
        end
        %i[pasted for_private_message for_site_setting].each do |key|
          parameters[key] = parameters[key].to_s unless parameters[key].nil?
        end
        context.dataloader.clear_cache
        UploadCreation.new(request: context[:request], request_method: "POST").call(parameters: parameters)
      ensure
        context.dataloader.clear_cache
      end

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
