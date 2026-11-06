module DiscourseGraphQL
  module Chat
    class DraftType < Types::BaseObject
      graphql_name "ChatDraft"

      field :channel_id, ID, null: false, hash_key: "channel_id"
      field :thread_id, ID, null: true, hash_key: "thread_id"
      field :serialized_data, String, null: false, hash_key: "data"
    end
  end
end
