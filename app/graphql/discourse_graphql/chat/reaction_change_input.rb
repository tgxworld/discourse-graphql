module DiscourseGraphQL
  module Chat
    class ReactionChangeInput < Types::BaseInputObject
      graphql_name "ChatReactionChangeInput"

      argument :channel_id, ID, required: true
      argument :message_id, ID, required: true
      argument :emoji, String, required: true
      argument :action, ReactionAction, required: true
    end
  end
end
