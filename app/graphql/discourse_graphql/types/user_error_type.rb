module DiscourseGraphQL
  module Types
    class UserErrorType < BaseObject
      field :code, String, null: false
      field :message, String, null: false
      field :description, String, null: true
      field :field, [String], null: true
      field :retry_after_seconds, Int, null: true
    end
  end
end
