module DiscourseGraphQL
  module Chat
    class MessageCreationPayloadType < Types::BaseObject
      graphql_name "ChatMessageCreationPayload"

      field :status, MessageCreationStatus, null: false
      field :message_id, ID, null: true
      field :errors, [Types::UserErrorType], null: false
    end
  end
end
