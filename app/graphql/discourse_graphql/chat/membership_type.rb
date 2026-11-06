module DiscourseGraphQL
  module Chat
    class MembershipType < Types::BaseObject
      graphql_name "ChatMembership"

      field :channel_id, ID, null: false, hash_key: "chat_channel_id"
      field :following, Boolean, null: false
      field :muted, Boolean, null: false
      field :notification_level, NotificationLevel, null: false, hash_key: "notification_level"
      field :starred, Boolean, null: false
      field :last_read_message_id, ID, null: true, hash_key: "last_read_message_id"
      field :last_viewed_at, GraphQL::Types::ISO8601DateTime, null: true, hash_key: "last_viewed_at"
      field :last_viewed_pins_at,
            Types::NativeTimestamp,
            null: true,
            hash_key: "last_viewed_pins_at"
      field :has_unseen_pins, Boolean, null: true, hash_key: "has_unseen_pins"
    end
  end
end
