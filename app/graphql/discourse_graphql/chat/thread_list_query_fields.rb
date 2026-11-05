module DiscourseGraphQL
  module Chat
    module ThreadListQueryFields
      def self.included(type)
        %i[chat_channel_threads current_user_chat_threads].each do |name|
          type.field name, ThreadPageType, null: true do
            extras [:lookahead]
            argument :channel_id, GraphQL::Types::ID, required: true if name == :chat_channel_threads
            argument :first, Integer, required: false, default_value: 10, replace_null_with_default: true
            argument :after, String, required: false
            complexity ->(_context, arguments, child) { 1000 + arguments[:first].clamp(1, 10) * (20 + child) }
          end
        end
      end

      def self.capability
        { id: "chat.threadLists", available: Discourse.plugins_by_name.fetch("chat").enabled?, query_fields: %w[chatChannelThreads currentUserChatThreads], mutation_fields: [] }
      end

      def chat_channel_threads(channel_id:, first:, lookahead:, after: nil)
        Extensions.ensure_enabled!("chat")
        ChannelThreads.new(request: context[:request], request_method: "GET").call(channel_id: channel_id, first: first, lookahead: lookahead, after: after)
      end

      def current_user_chat_threads(first:, lookahead:, after: nil)
        Extensions.ensure_enabled!("chat")
        CurrentUserThreads.new(request: context[:request], request_method: "GET").call(first: first, lookahead: lookahead, after: after)
      end
    end
  end
end
