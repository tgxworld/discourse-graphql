module DiscourseGraphQL
  module Chat
    module ThreadHistoryQueryFields
      def self.included(type)
        type.field :chat_thread_messages, ThreadMessagePageType, null: true do
          extras [:lookahead]
          argument :channel_id, GraphQL::Types::ID, required: true
          argument :thread_id, GraphQL::Types::ID, required: true
          argument :last, Integer, required: false, default_value: 25, replace_null_with_default: true
          argument :before, String, required: false
          complexity ->(_context, arguments, child) { 100 + arguments[:last].clamp(1, 50) * (20 + child) }
        end
      end

      def self.capability
        {
          id: "chat.threadMessageHistory",
          available: Discourse.plugins_by_name.fetch("chat").enabled?,
          query_fields: ["chatThreadMessages"],
          mutation_fields: [],
        }
      end

      def chat_thread_messages(channel_id:, thread_id:, last:, lookahead:, before: nil)
        Extensions.ensure_enabled!("chat")
        ThreadMessageHistory.new(request: context[:request], request_method: "GET").call(
          channel_id: channel_id,
          thread_id: thread_id,
          last: last,
          before: before,
          lookahead: lookahead,
        )
      end
    end
  end
end
