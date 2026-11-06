module DiscourseGraphQL
  class BookmarkDeletion < ::BookmarksController
    include NativeRequest
    include BookmarkResult

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:destroy)
      bookmark_result
    end
  end
end
