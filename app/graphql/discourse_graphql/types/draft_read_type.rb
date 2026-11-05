module DiscourseGraphQL
  module Types
    class DraftReadType < BaseObject
      field :key, String, null: false
      field :sequence, GraphQL::Types::BigInt, null: false
      field :content, DraftContentType, null: true
    end
  end
end
