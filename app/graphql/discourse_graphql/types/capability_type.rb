module DiscourseGraphQL
  module Types
    class CapabilityType < BaseObject
      field :id, ID, null: false
      field :available, Boolean, null: false
      field :query_fields, [String], null: false
      field :mutation_fields, [String], null: false
    end
  end
end
