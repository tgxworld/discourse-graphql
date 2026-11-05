module DiscourseGraphQL
  class DraftDelete < ::DraftsController
    include NativeRequest
    include DraftResult

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:destroy)
      draft_result
    end
  end
end
