module Types
  class QueryType < Types::BaseObject
    # Add root-level fields here.
    # They will be entry points for queries on your schema.
    field :search, GroupedSearchResultsType, null: true do
      description 'Search for posts'
      argument :term, String, required: true
      argument :page, Int, required: false
    end

    field :latest_topics, [TopicType], null: false do
      description 'Latest topics'
      argument :page, Int, required: false
    end

    def search(term:, page: 1)
      if term.length < SiteSetting.min_search_term_length
        raise GraphQL::ExecutionError, "Your search term is too short."
      end

      search_args = {
        type_filter: 'topic',
        guardian: context[:guardian],
        blurb_length: 300,
        page: page,
      }

      Search.new(term, search_args).execute
    end

    def latest_topics(page: 0)
      TopicQuery.new(context[:guardian].user,
        guardian: context[:guardian],
        page: page
      ).list_latest.topics
    end
  end
end
