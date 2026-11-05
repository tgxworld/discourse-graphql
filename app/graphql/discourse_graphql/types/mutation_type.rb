module DiscourseGraphQL
  module Types
    class MutationType < Types::BaseObject
      Extensions.mutation_modules.each { |extension| include extension }

      field :create_topic, PostCreationPayloadType, null: false, complexity: 1000 do
        argument :input, CreateTopicInput, required: true
      end

      field :create_post, PostCreationPayloadType, null: false, complexity: 1000 do
        argument :input, CreatePostInput, required: true
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

      def create(parameters:)
        context.dataloader.clear_cache
        result = PostCreation.new(request: context[:request]).call(parameters: parameters)
        context.dataloader.clear_cache
        result
      end
    end
  end
end
