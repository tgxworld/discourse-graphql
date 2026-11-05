module DiscourseGraphQL
  module Chat
    class ThreadCreationPayloadType < Types::BaseObject
      graphql_name "ChatThreadCreatePayload"

      field :success, Boolean, null: false
      field :thread, ThreadType, null: true
      field :errors, [Types::UserErrorType], null: false
    end
  end
end
