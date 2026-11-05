module DiscourseGraphQL
  module Types
    class SiteSettingObjectValidationsType < BaseObject
      field :min_length, GraphQL::Types::BigInt, null: true, hash_key: "min_length"
      field :max_length, GraphQL::Types::BigInt, null: true, hash_key: "max_length"
    end
  end
end
