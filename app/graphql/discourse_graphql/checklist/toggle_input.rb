module DiscourseGraphQL
  module Checklist
    class ToggleInput < Types::BaseInputObject
      graphql_name "ChecklistToggleInput"

      argument :checkbox_index, Integer, required: true
      argument :checkbox_source, String, required: false
      argument :checkbox_count, Integer, required: false
      argument :checked, GraphQL::Types::Boolean, required: true
    end
  end
end
