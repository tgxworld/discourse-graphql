module DiscourseGraphQL
  module Chat
    module PinMutationFields
      def self.included(type)
        type.field :pin_chat_message, Types::ActionPayloadType, null: true, complexity: 1000 do
          argument :channel_id, GraphQL::Types::ID, required: true
          argument :message_id, GraphQL::Types::ID, required: true
        end
        type.field :unpin_chat_message, Types::ActionPayloadType, null: true, complexity: 1000 do
          argument :channel_id, GraphQL::Types::ID, required: true
          argument :message_id, GraphQL::Types::ID, required: true
        end
        type.field :mark_chat_pins_read, Types::ActionPayloadType, null: true, complexity: 1000 do
          argument :channel_id, GraphQL::Types::ID, required: true
        end
      end

      def self.capability
        {
          id: "chat.pinControls",
          available:
            Discourse.plugins_by_name.fetch("chat").enabled? && SiteSetting.chat_pinned_messages,
          query_fields: [],
          mutation_fields: %w[pinChatMessage unpinChatMessage markChatPinsRead],
        }
      end

      def pin_chat_message(channel_id:, message_id:)
        perform_pin_control(
          adapter: MessagePinning,
          parameters: {
            channel_id: channel_id,
            message_id: message_id,
          },
          request_method: "POST",
        )
      end

      def unpin_chat_message(channel_id:, message_id:)
        perform_pin_control(
          adapter: MessageUnpinning,
          parameters: {
            channel_id: channel_id,
            message_id: message_id,
          },
          request_method: "DELETE",
        )
      end

      def mark_chat_pins_read(channel_id:)
        perform_pin_control(
          adapter: MarkPinsRead,
          parameters: {
            channel_id: channel_id,
          },
          request_method: "PUT",
        )
      end

      private

      def perform_pin_control(adapter:, parameters:, request_method:)
        Extensions.ensure_enabled!("chat")
        context.dataloader.clear_cache
        adapter.new(request: context[:request], request_method: request_method).call(
          parameters: parameters,
        )
      ensure
        context.dataloader.clear_cache
      end
    end
  end
end
