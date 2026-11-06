module DiscourseGraphQL
  module Chat
    class MarkPinsRead < ::Chat::Api::ChannelPinsController
      include NativeRequest

      def call(parameters:)
        self.params = ActionController::Parameters.new(parameters)
        process(:mark_read)
        NativeResponse.new(response).action_payload
      end
    end
  end
end
