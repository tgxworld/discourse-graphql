module DiscourseGraphQL
  module Chat
    class MessageCreation < ::Chat::Api::ChannelMessagesController
      include NativeRequest

      def call(parameters:)
        self.params = ActionController::Parameters.new(parameters)
        process(:create)
        result = NativeResponse.new(response)
        payload = result.payload
        successful = result.successful?

        {
          status: successful ? "CREATED" : "FAILED",
          message_id: payload["message_id"],
          errors: result.errors,
        }
      end
    end
  end
end
