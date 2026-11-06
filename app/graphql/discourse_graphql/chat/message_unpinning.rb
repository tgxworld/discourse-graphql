module DiscourseGraphQL
  module Chat
    class MessageUnpinning < ::Chat::Api::ChannelPinsController
      include NativeRequest

      def call(parameters:)
        self.params = ActionController::Parameters.new(parameters)
        process(:destroy)
        NativeResponse.new(response).action_payload
      end
    end
  end
end
