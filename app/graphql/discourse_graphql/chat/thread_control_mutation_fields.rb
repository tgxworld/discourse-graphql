module DiscourseGraphQL
  module Chat
    module ThreadControlMutationFields
      def self.included(type)
        type.field :update_chat_thread_title,
                   Types::ActionPayloadType,
                   null: true,
                   complexity: 1000 do
          argument :thread_id, GraphQL::Types::ID, required: true
          argument :title, String, required: false
        end
        type.field :mark_chat_thread_read, Types::ActionPayloadType, null: true, complexity: 1000 do
          argument :channel_id, GraphQL::Types::ID, required: true
          argument :thread_id, GraphQL::Types::ID, required: true
          argument :message_id, GraphQL::Types::ID, required: false
        end
        type.field :update_chat_thread_notifications,
                   ThreadMembershipPayloadType,
                   null: true,
                   complexity: 1000 do
          extras [:lookahead]
          argument :channel_id, GraphQL::Types::ID, required: true
          argument :thread_id, GraphQL::Types::ID, required: true
          argument :notification_level, ThreadNotificationLevel, required: true
        end
        type.field :mark_chat_thread_title_prompt_seen,
                   ThreadMembershipPayloadType,
                   null: true,
                   complexity: 1000 do
          extras [:lookahead]
          argument :channel_id, GraphQL::Types::ID, required: true
          argument :thread_id, GraphQL::Types::ID, required: true
        end
      end

      def self.capability
        {
          id: "chat.threadControls",
          available: Discourse.plugins_by_name.fetch("chat").enabled?,
          query_fields: [],
          mutation_fields: %w[
            updateChatThreadTitle
            markChatThreadRead
            updateChatThreadNotifications
            markChatThreadTitlePromptSeen
          ],
        }
      end

      def update_chat_thread_title(thread_id:, title: nil)
        perform_thread_control(
          adapter: UpdateThreadTitle,
          parameters: {
            thread_id: thread_id,
            title: title,
          },
        )
      end

      def mark_chat_thread_read(channel_id:, thread_id:, message_id: nil)
        perform_thread_control(
          adapter: MarkThreadRead,
          parameters: {
            channel_id: channel_id,
            thread_id: thread_id,
            message_id: message_id,
          },
        )
      end

      def update_chat_thread_notifications(channel_id:, thread_id:, notification_level:, lookahead:)
        perform_thread_control(
          adapter: UpdateThreadNotifications,
          parameters: {
            channel_id: channel_id,
            thread_id: thread_id,
            notification_level: notification_level,
          },
          lookahead: lookahead,
        )
      end

      def mark_chat_thread_title_prompt_seen(channel_id:, thread_id:, lookahead:)
        perform_thread_control(
          adapter: MarkThreadTitlePromptSeen,
          parameters: {
            channel_id: channel_id,
            thread_id: thread_id,
          },
          request_method: "POST",
          lookahead: lookahead,
        )
      end

      private

      def perform_thread_control(adapter:, parameters:, request_method: "PUT", lookahead: nil)
        Extensions.ensure_enabled!("chat")
        context.dataloader.clear_cache
        options = { parameters: parameters }
        options[:fields] = lookahead
          .selection(:membership)
          .selections
          .map { |selection| selection.field.method_sym } if lookahead
        adapter.new(request: context[:request], request_method: request_method).call(**options)
      ensure
        context.dataloader.clear_cache
      end
    end
  end
end
