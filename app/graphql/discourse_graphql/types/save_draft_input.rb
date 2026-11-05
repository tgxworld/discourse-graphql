module DiscourseGraphQL
  module Types
    class SaveDraftInput < BaseInputObject
      argument :key, String, required: true
      argument :sequence, GraphQL::Types::BigInt, required: true
      argument :content, DraftContentInput, required: true
      argument :owner, String, required: false
      argument :force_save, Boolean, required: false, default_value: false, replace_null_with_default: true
    end
  end
end
