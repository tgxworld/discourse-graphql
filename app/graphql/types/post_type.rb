module Types
  class PostType < Types::BaseObject
    description "Post"

    field :id, ID, null: false
    field :post_number, Int, null: false
    field :cooked, String, null: false
  end
end
