module DiscourseGraphQL
  module Chat
    class ChannelThreads < ::Chat::Api::ChannelThreadsController
      include NativeRequest
      include ThreadListResult

      def call(channel_id:, first:, lookahead:, after: nil)
        prepare_thread_page(kind: "channel", channel_id: channel_id, first: first, lookahead: lookahead, after: after)
        process(:index)
        thread_page
      end
    end
  end
end
