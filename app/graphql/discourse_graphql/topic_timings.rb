module DiscourseGraphQL
  class TopicTimings < ::TopicsController
    include NativeRequest

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:timings)
      NativeResponse.new(response).action_payload
    end
  end
end
