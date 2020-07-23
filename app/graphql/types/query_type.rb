module Types
  class QueryType < Types::BaseObject
    # Add root-level fields here.
    # They will be entry points for queries on your schema.
    field :search, GroupedSearchResultsType, null: true do
      description 'Search for posts'
      argument :query, String, required: true
    end

    def search(query:)
      search_args = {
        type_filter: 'topic',
        guardian: context[:guardian],
        blurb_length: 300
      }

      Search.new(query, search_args).execute
    end
  end
end
