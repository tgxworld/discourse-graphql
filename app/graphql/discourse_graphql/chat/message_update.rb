module DiscourseGraphQL
  module Chat
    class MessageUpdate < ::Chat::Api::ChannelMessagesController
      include NativeRequest

      def call(parameters:)
        self.params = ActionController::Parameters.new(parameters)
        process(:update)
        NativeResponse.new(response).action_payload
      end
    end
  end
end
