module DiscourseGraphQL
  class BookmarkBulk < ::BookmarksController
    include NativeRequest
    include BookmarkResult

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:bulk)
      bookmark_result
    end
  end
end
