module DiscourseGraphQL
  module Chat
    class ThreadMetaType < Types::BaseObject
      graphql_name "ChatThreadMeta"

      field :message_bus_last_ids, ThreadBusPositionType, null: true, hash_key: "message_bus_last_ids"
    end
  end
end
