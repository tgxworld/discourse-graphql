module DiscourseGraphQL
  module Types
    class DraftPayloadType < BaseObject
      field :success, Boolean, null: false
      field :sequence, GraphQL::Types::BigInt, null: true
      field :conflict_user, DraftConflictUserType, null: true
      field :deleted_count, Int, null: true
      field :errors, [UserErrorType], null: false
    end
  end
end
