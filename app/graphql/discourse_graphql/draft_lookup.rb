module DiscourseGraphQL
  class DraftLookup < ::DraftsController
    include NativeRequest

    def call(key:, sequence: nil)
      DraftParameters.validate!(key: key, sequence: sequence)
      parameters = { id: key }
      parameters[:sequence] = sequence unless sequence.nil?
      self.params = ActionController::Parameters.new(parameters)
      process(:show)
      result = NativeResponse.new(response)
      result.raise_error!
      {
        key: key,
        sequence: result.payload.fetch("draft_sequence"),
        content: DraftContent.decode(result.payload["draft"]),
      }
    end
  end
end
