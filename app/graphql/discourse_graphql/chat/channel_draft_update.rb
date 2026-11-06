module DiscourseGraphQL
  module Chat
    class ChannelDraftUpdate < ::Chat::Api::ChannelsDraftsController
      include NativeRequest

      def call(parameters:)
        self.params = ActionController::Parameters.new(parameters)
        process(:create)
        NativeResponse.new(response).action_payload
      end
    end
  end
end
