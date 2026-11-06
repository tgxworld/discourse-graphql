module DiscourseGraphQL
  module Chat
    class MessageRestoration < ::Chat::Api::ChannelMessagesController
      include NativeRequest

      def call(parameters:)
        self.params = ActionController::Parameters.new(parameters)
        process(:restore)
        NativeResponse.new(response).action_payload
      end
    end
  end
end
