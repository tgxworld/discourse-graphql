module DiscourseGraphQL
  module Types
    class DraftReplyUserInput < BaseInputObject
      argument :id, GraphQL::Types::BigInt, required: false
      argument :username, String, required: false
      argument :name, String, required: false
      argument :avatar_template, String, required: false
    end
  end
end
