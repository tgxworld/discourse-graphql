module DiscourseGraphQL
  module Chat
    class MessageCreationStatus < Types::BaseEnum
      graphql_name "ChatMessageCreationStatus"

      value "CREATED"
      value "FAILED"
    end
  end
end
