module DiscourseGraphQL
  module Checklist
    class UpdatePayloadType < Types::BaseObject
      graphql_name "ChecklistUpdatePayload"

      field :success, GraphQL::Types::Boolean, null: false
      field :errors, [Types::UserErrorType], null: false
      field :raw, String, null: true, hash_key: "raw"
      field :cooked, String, null: true, hash_key: "cooked"
      field :updated_at, String, null: true, hash_key: "updated_at"
      field :last_editor_id, GraphQL::Types::ID, null: true, hash_key: "last_editor_id"
      field :version, Integer, null: true, hash_key: "version"
      field :revised, GraphQL::Types::Boolean, null: true, hash_key: "revised"
      field :retryable, GraphQL::Types::Boolean, null: true, hash_key: "retryable"
    end
  end
end
