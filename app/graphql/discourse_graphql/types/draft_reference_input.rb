module DiscourseGraphQL
  module Types
    class DraftReferenceInput < BaseInputObject
      argument :key, String, required: true
      argument :sequence, GraphQL::Types::BigInt, required: true
    end
  end
end
