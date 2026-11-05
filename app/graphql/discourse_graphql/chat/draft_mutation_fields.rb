module DiscourseGraphQL
  module Chat
    module DraftMutationFields
      def self.included(type)
        type.field :update_chat_channel_draft, Types::ActionPayloadType, null: true, complexity: 1000 do
          argument :channel_id, GraphQL::Types::ID, required: true
          argument :serialized_data, String, required: false
        end
        type.field :update_chat_thread_draft, Types::ActionPayloadType, null: true, complexity: 1000 do
          argument :channel_id, GraphQL::Types::ID, required: true
          argument :thread_id, GraphQL::Types::ID, required: true
          argument :serialized_data, String, required: false
        end
      end

      def self.capability
        {
          id: "chat.draftChanges",
          available: Discourse.plugins_by_name.fetch("chat").enabled?,
          query_fields: [],
          mutation_fields: %w[updateChatChannelDraft updateChatThreadDraft],
        }
      end

      def update_chat_channel_draft(channel_id:, serialized_data: nil)
        perform_chat_draft_change(adapter: ChannelDraftUpdate, parameters: { channel_id: channel_id, data: serialized_data })
      end

      def update_chat_thread_draft(channel_id:, thread_id:, serialized_data: nil)
        perform_chat_draft_change(adapter: ThreadDraftUpdate, parameters: { channel_id: channel_id, thread_id: thread_id, data: serialized_data })
      end

      private

      def perform_chat_draft_change(adapter:, parameters:)
        Extensions.ensure_enabled!("chat")
        context.dataloader.clear_cache
        context.namespace(:chat_draft_windows).clear
        adapter.new(request: context[:request], request_method: "POST").call(parameters: parameters)
      ensure
        context.dataloader.clear_cache
        context.namespace(:chat_draft_windows).clear
      end
    end
  end
end
