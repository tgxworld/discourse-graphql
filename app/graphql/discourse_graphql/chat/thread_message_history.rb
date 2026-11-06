module DiscourseGraphQL
  module Chat
    class ThreadMessageHistory < ::Chat::Api::ChannelThreadMessagesController
      include NativeRequest
      include MessageHistoryResult

      def call(channel_id:, thread_id:, last:, lookahead:, before: nil)
        prepare_message_page(
          last: last,
          lookahead: lookahead,
          scope: { "channel_id" => channel_id, "thread_id" => thread_id },
          purpose: "discourse_graphql_chat_thread_history",
          before: before,
        )
        self.params = ActionController::Parameters.new(
          channel_id: channel_id,
          thread_id: thread_id,
          page_size: last,
          direction: "past",
          fetch_from_last_message: @before_boundary.nil?,
          target_message_id: @before_boundary&.fetch(:message_id),
        )
        process(:index)
        message_page
      end
    end
  end
end
