module Types
  class GroupedSearchResultsType < Types::BaseObject
    description "GroupedSearchResult"

    field :posts, [SearchPostType], null: false

    def posts
      context.scoped_set!(:result, object)
      object.posts
    end
  end
end
