module DiscourseGraphQL
  module Chat
    module MessageMutationFields
      def self.included(type)
        type.field :update_chat_message, Types::ActionPayloadType, null: true do
          argument :input, UpdateMessageInput, required: true
          complexity ->(_context, arguments, child) do
                       1000 + 20 * arguments[:input][:upload_ids].to_a.size + child
                     end
        end
        type.field :delete_chat_message, Types::ActionPayloadType, null: true, complexity: 1000 do
          argument :channel_id, GraphQL::Types::ID, required: true
          argument :message_id, GraphQL::Types::ID, required: true
        end
        type.field :restore_chat_message, Types::ActionPayloadType, null: true, complexity: 1000 do
          argument :channel_id, GraphQL::Types::ID, required: true
          argument :message_id, GraphQL::Types::ID, required: true
        end
        type.field :delete_chat_messages, Types::ActionPayloadType, null: true do
          argument :channel_id, GraphQL::Types::ID, required: true
          argument :message_ids, [GraphQL::Types::ID], required: true
          complexity ->(_context, arguments, child) do
                       1000 + 20 * arguments[:message_ids].size + child
                     end
        end
      end

      def self.capability
        {
          id: "chat.messageChanges",
          available: Discourse.plugins_by_name.fetch("chat").enabled?,
          query_fields: [],
          mutation_fields: %w[
            updateChatMessage
            deleteChatMessage
            deleteChatMessages
            restoreChatMessage
          ],
        }
      end

      def update_chat_message(input:)
        perform_message_change(
          adapter: MessageUpdate,
          parameters: input.to_h,
          request_method: "PUT",
        )
      end

      def delete_chat_message(channel_id:, message_id:)
        perform_message_change(
          adapter: MessageDeletion,
          parameters: {
            channel_id: channel_id,
            message_id: message_id,
          },
          request_method: "DELETE",
        )
      end

      def restore_chat_message(channel_id:, message_id:)
        perform_message_change(
          adapter: MessageRestoration,
          parameters: {
            channel_id: channel_id,
            message_id: message_id,
          },
          request_method: "PUT",
        )
      end

      def delete_chat_messages(channel_id:, message_ids:)
        raise Discourse::InvalidParameters unless message_ids.size.between?(1, 200)
        perform_message_change(
          adapter: MessageBulkDeletion,
          parameters: {
            channel_id: channel_id,
            message_ids: message_ids,
          },
          request_method: "DELETE",
        )
      end

      private

      def perform_message_change(adapter:, parameters:, request_method:)
        Extensions.ensure_enabled!("chat")
        MessageInputLimits.validate_upload_ids!(parameters[:upload_ids])
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
