module DiscourseGraphQL
  module Types
    class UserType < BaseObject
      field :id, ID, null: false
      field :username, String, null: false
    end
  end
end
