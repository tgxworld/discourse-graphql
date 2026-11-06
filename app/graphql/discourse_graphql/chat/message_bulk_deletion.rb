module DiscourseGraphQL
  module Chat
    class MessageBulkDeletion < ::Chat::Api::ChannelMessagesController
      include NativeRequest

      def call(parameters:)
        self.params = ActionController::Parameters.new(parameters)
        process(:bulk_destroy)
        NativeResponse.new(response).action_payload
      end
    end
  end
end
