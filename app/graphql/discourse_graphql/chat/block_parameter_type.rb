module DiscourseGraphQL
  module Chat
    class BlockParameterType < Types::BaseObject
      graphql_name "ChatBlockParameter"

      field :label, String, null: true, hash_key: "label"
      field :value, String, null: true, hash_key: "value"
      field :color, String, null: true, hash_key: "color"
    end
  end
end
