module DiscourseGraphQL
  module Chat
    class CreateMessageInput < Types::BaseInputObject
      graphql_name "CreateChatMessageInput"

      argument :channel_id, ID, required: true
      argument :message, String, required: true
      argument :in_reply_to_id, ID, required: false
      argument :thread_id, ID, required: false
      argument :staged_id, String, required: false
    end
  end
end
