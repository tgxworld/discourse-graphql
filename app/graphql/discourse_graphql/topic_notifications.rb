module DiscourseGraphQL
  class TopicNotifications < ::TopicsController
    include NativeRequest

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:set_notifications)
      NativeResponse.new(response).action_payload
    end
  end
end
