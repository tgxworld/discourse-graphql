module DiscourseGraphQL
  module DraftResult
    private

    def draft_result
      result = NativeResponse.new(response)
      result.action_payload.merge(
        sequence: result.payload["draft_sequence"],
        conflict_user: result.payload["conflict_user"],
        deleted_count: result.payload["deleted_count"],
      )
    end
  end
end
