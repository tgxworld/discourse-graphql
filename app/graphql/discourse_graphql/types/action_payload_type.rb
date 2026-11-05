module DiscourseGraphQL
  module Types
    class ActionPayloadType < BaseObject
      field :success, Boolean, null: false
      field :errors, [UserErrorType], null: false
    end
  end
end
