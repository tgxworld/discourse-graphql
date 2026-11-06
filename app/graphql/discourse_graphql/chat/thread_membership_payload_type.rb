module DiscourseGraphQL
  module Chat
    class ThreadMembershipPayloadType < Types::BaseObject
      graphql_name "ChatThreadMembershipPayload"

      field :success, Boolean, null: false
      field :membership, ThreadMembershipType, null: true
      field :errors, [Types::UserErrorType], null: false
    end
  end
end
