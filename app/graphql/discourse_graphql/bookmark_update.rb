module DiscourseGraphQL
  class BookmarkUpdate < ::BookmarksController
    include NativeRequest
    include BookmarkResult

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:update)
      bookmark_result
    end
  end
end
