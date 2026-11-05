# frozen_string_literal: true

module DiscourseGraphQL
  module Types
    class QueryType < Types::BaseObject
      field :current_user, UserType, null: true

      field :topic, TopicType, null: true do
        argument :id, ID, required: true
      end

      field :categories, [CategoryType], null: false do
        description 'List of categories that user has access to'
      end

      field :search, [SearchPostType], null: true do
        description 'Search for posts'
        argument :term, String, required: true
        argument :page, Int, required: false, default_value: 1, replace_null_with_default: true
        complexity ->(_context, _arguments, child_complexity) do
          1 + ::Search.per_filter * child_complexity
        end
      end

      field :latest_topics, [TopicType], null: false do
        description 'Latest topics'
        argument :page, Int, required: false, default_value: 0, replace_null_with_default: true
        argument :category_id, Int, required: false
        argument :limit, Int, required: false, default_value: 30, replace_null_with_default: true
        complexity ->(_context, arguments, child_complexity) do
          1 + arguments[:limit].clamp(1, 50) * child_complexity
        end
      end

      def search(term:, page: 1)
        result = SearchQuery.new(request: context[:request]).call(term: term, page: page)
        ActiveRecord::Associations::Preloader.new(
          records: result.posts,
          associations: [:post_search_data, :user, { topic: [:category, :shared_draft] }],
        ).call
        context.scoped_set!(:result, result)
        result.posts
      end

      def current_user
        context[:guardian].user.presence
      end

      def topic(id:)
        dataloader.with(Loaders::RecordLoader, Topic).load(id)
      end

      def latest_topics(page: 0, category_id: nil, limit:)
        if !limit.between?(1, 50) || page.negative?
          raise GraphQL::ExecutionError.new(
            I18n.t("discourse_graphql.errors.invalid_page"),
            extensions: { code: "BAD_USER_INPUT" },
          )
        end

        opts = {
          guardian: context[:guardian],
          page: page,
          per_page: limit,
          category: category_id
        }

        topics = TopicQuery.new(context[:guardian].user, opts).list_latest.topics
        ActiveRecord::Associations::Preloader.new(
          records: topics,
          associations: :shared_draft,
        ).call
        topics
      end

      def categories
        CategoryList.new(context[:guardian]).categories
      end
    end
  end
end
