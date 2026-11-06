module DiscourseGraphQL
  module Chat
    class ReactionChange < ::Chat::ChatController
      include NativeRequest

      def call(parameters:)
        self.params = ActionController::Parameters.new(parameters)
        process(:react)
        NativeResponse.new(response).action_payload
      end
    end
  end
end
