module DiscourseGraphQL
  module Chat
    class CategoryElementType < Types::BaseObject
      graphql_name "ChatCategoryElement"

      field :type, String, null: true, hash_key: "type"
      field :title, String, null: true, hash_key: "title"
      field :color, String, null: true, hash_key: "color"
      field :description, String, null: true, hash_key: "description"
      field :url, String, null: true, hash_key: "url"
      field :parent_name, String, null: true, hash_key: "parent_name"
      field :parent_color, String, null: true, hash_key: "parent_color"
    end
  end
end
