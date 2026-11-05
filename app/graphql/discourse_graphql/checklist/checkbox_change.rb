module DiscourseGraphQL
  module Checklist
    class CheckboxChange < ::Checklist::CheckboxesController
      include NativeRequest

      def call(parameters:)
        self.params = ActionController::Parameters.new(parameters)
        process(:toggle)
        result = NativeResponse.new(response)
        result.action_payload.merge(result.payload.slice("raw", "cooked", "updated_at", "last_editor_id", "version", "revised", "retryable"))
      end
    end
  end
end
