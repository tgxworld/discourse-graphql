module DiscourseGraphQL
  module Chat
    module MutationFields
      def self.included(type)
        type.field :create_chat_message, MessageCreationPayloadType, null: true, complexity: 1000 do
          argument :input, CreateMessageInput, required: true
        end
      end

      def self.capability
        {
          id: "chat.messageCreation",
          available: Discourse.plugins_by_name.fetch("chat").enabled?,
          query_fields: [],
          mutation_fields: ["createChatMessage"],
        }
      end

      def create_chat_message(input:)
        if !Discourse.plugins_by_name.fetch("chat").enabled?
          raise GraphQL::ExecutionError.new(
            I18n.t("discourse_graphql.errors.feature_disabled"),
            extensions: { code: "FEATURE_DISABLED" },
          )
        end

        parameters = input.to_h
        parameters[:chat_channel_id] = parameters.delete(:channel_id)
        context.dataloader.clear_cache
        MessageCreation.new(request: context[:request]).call(parameters: parameters)
      ensure
        context.dataloader.clear_cache
      end
    end
  end
end
