module DiscourseGraphQL
  module Chat
    class ThreadMembershipType < Types::BaseObject
      graphql_name "ChatThreadMembership"

      field :thread_id, ID, null: true, hash_key: "thread_id"
      field :last_read_message_id, ID, null: true, hash_key: "last_read_message_id"
      field :notification_level, ThreadNotificationLevel, null: true, hash_key: "notification_level"
      field :thread_title_prompt_seen, Boolean, null: true, hash_key: "thread_title_prompt_seen"
    end
  end
end
