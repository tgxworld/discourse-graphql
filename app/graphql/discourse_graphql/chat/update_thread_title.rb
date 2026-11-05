module DiscourseGraphQL
  module Chat
    class UpdateThreadTitle < ::Chat::Api::ChannelThreadsController
      include NativeRequest

      def call(parameters:)
        self.params = ActionController::Parameters.new(parameters)
        process(:update)
        NativeResponse.new(response).action_payload
      end
    end
  end
end
