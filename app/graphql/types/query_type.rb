module Types
  class QueryType < Types::BaseObject
    # Add root-level fields here.
    # They will be entry points for queries on your schema.

    field :post, PostType, null: true do
      description 'Find a Post by ID'
      argument :id, ID, required: true
    end

    def post(id:)
      Post.find_by(id: id)
    end
  end
end
