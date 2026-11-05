module DiscourseGraphQL
  module Chat
    class MembershipPayloadType < Types::BaseObject
      graphql_name "ChatMembershipPayload"

      field :success, Boolean, null: false
      field :membership, MembershipType, null: true
      field :updated_count, Int, null: true
      field :errors, [Types::UserErrorType], null: false
    end
  end
end
