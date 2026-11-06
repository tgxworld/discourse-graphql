module DiscourseGraphQL
  module Chat
    class BlockChangeType < Types::BaseObject
      graphql_name "ChatBlockChange"

      field :label, String, null: true, hash_key: "label"
      field :before, String, null: true, hash_key: "before"
      field :after, String, null: true, hash_key: "after"
      field :before_color, String, null: true, hash_key: "before_color"
      field :after_color, String, null: true, hash_key: "after_color"
    end
  end
end
