module DiscourseGraphQL
  class BookmarkPin < ::BookmarksController
    include NativeRequest
    include BookmarkResult

    def call(parameters:)
      self.params = ActionController::Parameters.new(parameters)
      process(:toggle_pin)
      bookmark_result
    end
  end
end
