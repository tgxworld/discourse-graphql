module DiscourseGraphQL
  module Chat
    class ChannelType < Types::BaseObject
      graphql_name "ChatChannel"

      field :id, ID, null: false
      field :title, String, null: false
      field :slug, String, null: true
      field :description, String, null: true
      field :status, String, null: false
      field :threading_enabled, Boolean, null: false, hash_key: "threading_enabled"
      field :memberships_count, Int, null: false, hash_key: "memberships_count"
    end
  end
end
