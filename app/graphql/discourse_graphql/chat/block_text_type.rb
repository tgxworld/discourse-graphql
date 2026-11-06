module DiscourseGraphQL
  module Chat
    class BlockTextType < Types::BaseObject
      graphql_name "ChatBlockText"

      field :type, String, null: true, hash_key: "type"
      field :text, String, null: true, hash_key: "text"
    end
  end
end
