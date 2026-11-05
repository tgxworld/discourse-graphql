module DiscourseGraphQL
  module Checklist
    class UpdateInput < Types::BaseInputObject
      graphql_name "ChecklistUpdateInput"

      argument :post_id, GraphQL::Types::ID, required: true
      argument :expected_raw, String, required: true
      argument :expected_updated_at, String, required: true
      argument :mutation_id, String, required: true
      argument :toggles, [ToggleInput], required: true
    end
  end
end
