module DiscourseGraphQL
  module Chat
    module ReactionMutationFields
      def self.included(type)
        type.field :update_chat_reaction, Types::ActionPayloadType, null: true, complexity: 1000 do
          argument :input, ReactionChangeInput, required: true
        end
      end

      def self.capability
        { id: "chat.reactionChanges", available: Discourse.plugins_by_name.fetch("chat").enabled?, query_fields: [], mutation_fields: ["updateChatReaction"] }
      end

      def update_chat_reaction(input:)
        Extensions.ensure_enabled!("chat")
        values = input.to_h
        ReactionInputLimits.validate_emoji_size!(values.fetch(:emoji))
        parameters = { chat_channel_id: values.fetch(:channel_id), message_id: values.fetch(:message_id), emoji: values.fetch(:emoji), react_action: values.fetch(:action) }
        context.dataloader.clear_cache
        ReactionChange.new(request: context[:request], request_method: "PUT").call(parameters: parameters)
      ensure
        context.dataloader.clear_cache
      end
    end
  end
end
