module DiscourseGraphQL
  class TopicReadingReset < ::TopicsController
    include NativeRequest

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:destroy_timings)
      NativeResponse.new(response).action_payload
    end
  end
end
