module DiscourseGraphQL
  module Types
    class DraftTagInput < BaseInputObject
      argument :id, GraphQL::Types::BigInt, required: false
      argument :name, String, required: false
      argument :slug, String, required: false
      argument :is_new, Boolean, required: false
      argument :format, DraftTagFormat, required: true
    end
  end
end
