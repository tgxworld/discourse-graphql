module DiscourseGraphQL
  module Chat
    class CurrentUserThreads < ::Chat::Api::CurrentUserThreadsController
      include NativeRequest
      include ThreadListResult

      def call(first:, lookahead:, after: nil)
        prepare_thread_page(kind: "current_user", first: first, lookahead: lookahead, after: after)
        process(:index)
        thread_page
      end
    end
  end
end
