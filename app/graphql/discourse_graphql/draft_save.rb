module DiscourseGraphQL
  class DraftSave < ::DraftsController
    include NativeRequest
    include DraftResult

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:create)
      draft_result
    end
  end
end
