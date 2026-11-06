module DiscourseGraphQL
  module Checklist
    module MutationFields
      def self.included(type)
        type.field :update_checklist, UpdatePayloadType, null: true do
          argument :input, UpdateInput, required: true
          complexity ->(_context, arguments, child) do
                       1000 +
                         arguments[:input][:toggles].size.clamp(
                           0,
                           ::Checklist::ToggleCheckbox::MAX_BATCH_SIZE,
                         ) * 20 + child
                     end
        end
      end

      def self.capability
        {
          id: "checklist.checkboxChanges",
          available: Discourse.plugins_by_name.fetch("checklist").enabled?,
          query_fields: [],
          mutation_fields: ["updateChecklist"],
        }
      end

      def update_checklist(input:)
        Extensions.ensure_enabled!("checklist")
        parameters = input.to_h
        if parameters[:toggles].size > ::Checklist::ToggleCheckbox::MAX_BATCH_SIZE
          raise Discourse::InvalidParameters
        end
        context.dataloader.clear_cache
        CheckboxChange.new(request: context[:request], request_method: "PUT").call(
          parameters: parameters,
        )
      ensure
        context.dataloader.clear_cache
      end
    end
  end
end
