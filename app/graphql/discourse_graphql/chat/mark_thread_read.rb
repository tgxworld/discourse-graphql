module DiscourseGraphQL
  module Chat
    class MarkThreadRead < ::Chat::Api::ChannelsThreadsReadController
      include NativeRequest

      def call(parameters:)
        self.params = ActionController::Parameters.new(parameters)
        process(:update)
        NativeResponse.new(response).action_payload
      end
    end
  end
end
