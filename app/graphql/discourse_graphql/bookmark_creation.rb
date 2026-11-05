module DiscourseGraphQL
  class BookmarkCreation < ::BookmarksController
    include NativeRequest
    include BookmarkResult

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:create)
      bookmark_result
    end
  end
end
