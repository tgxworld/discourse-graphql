module DiscourseGraphQL
  module Chat
    module MutationFields
      def self.included(type)
        type.field :create_chat_message, MessageCreationPayloadType, null: true do
          argument :input, CreateMessageInput, required: true
          complexity ->(_context, arguments, child) { 1000 + 20 * arguments[:input][:upload_ids].to_a.size + child }
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
        Extensions.ensure_enabled!("chat")

        parameters = input.to_h
        MessageInputLimits.validate_upload_ids!(parameters[:upload_ids])
        parameters[:chat_channel_id] = parameters.delete(:channel_id)
        context.dataloader.clear_cache
        MessageCreation.new(request: context[:request]).call(parameters: parameters)
      ensure
        context.dataloader.clear_cache
      end
    end
  end
end
