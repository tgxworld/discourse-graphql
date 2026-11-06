module DiscourseGraphQL
  class DraftBulkDelete < ::DraftsController
    include NativeRequest
    include DraftResult

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:bulk_destroy)
      draft_result
    end
  end
end
