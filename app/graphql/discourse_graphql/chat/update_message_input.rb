module DiscourseGraphQL
  module Chat
    class UpdateMessageInput < Types::BaseInputObject
      graphql_name "UpdateChatMessageInput"

      argument :channel_id, ID, required: true
      argument :message_id, ID, required: true
      argument :message, String, required: false
      argument :upload_ids, [ID], required: false
    end
  end
end
