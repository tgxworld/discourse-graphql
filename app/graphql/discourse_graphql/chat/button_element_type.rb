module DiscourseGraphQL
  module Chat
    class ButtonElementType < Types::BaseObject
      graphql_name "ChatButtonElement"

      field :type, String, null: true, hash_key: "type"
      field :action_id, String, null: true, hash_key: "action_id"
      field :text, BlockTextType, null: true, hash_key: "text"
      field :style, String, null: true, hash_key: "style"
      field :icon, String, null: true, hash_key: "icon"
    end
  end
end
