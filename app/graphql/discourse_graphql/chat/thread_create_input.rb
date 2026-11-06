module DiscourseGraphQL
  module Chat
    class ThreadCreateInput < Types::BaseInputObject
      graphql_name "ChatThreadCreateInput"
      argument :channel_id, ID, required: true
      argument :original_message_id, ID, required: true
      argument :title, String, required: false
    end
  end
end
