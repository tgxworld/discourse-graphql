module DiscourseGraphQL
  module BookmarkResult
    private

    def bookmark_result
      result = NativeResponse.new(response)
      result.action_payload.merge(
        id: result.payload["id"],
        changed_ids: result.payload["bookmark_ids"],
        topic_bookmarked: result.payload["topic_bookmarked"],
      )
    end
  end
end
