module DiscourseGraphQL
  module Chat
    class MessageHistory < ::Chat::Api::ChannelMessagesController
      include NativeRequest
      include MessageHistoryResult

      def call(channel_id:, last:, lookahead:, before: nil)
        prepare_message_page(
          last: last,
          lookahead: lookahead,
          scope: {
            "channel_id" => channel_id,
          },
          purpose: "discourse_graphql_chat_history",
          before: before,
        )
        self.params =
          ActionController::Parameters.new(
            channel_id: channel_id,
            page_size: last,
            direction: "past",
            target_message_id: @before_boundary&.fetch(:message_id),
          )
        process(:index)
        message_page
      end
    end
  end
end
