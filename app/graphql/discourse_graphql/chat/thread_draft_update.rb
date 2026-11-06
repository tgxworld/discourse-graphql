module DiscourseGraphQL
  module Chat
    class ThreadDraftUpdate < ::Chat::Api::ChannelsThreadsDraftsController
      include NativeRequest

      def call(parameters:)
        raise Discourse::InvalidParameters if parameters[:thread_id].blank?
        self.params = ActionController::Parameters.new(parameters)
        process(:create)
        NativeResponse.new(response).action_payload
      end
    end
  end
end
