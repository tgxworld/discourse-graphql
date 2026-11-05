# frozen_string_literal: true

module DiscourseGraphQL
  module Types
    class QueryType < Types::BaseObject
      Extensions.query_modules.each { |extension| include extension }

      field :capabilities, [CapabilityType], null: false
      field :current_user, UserType, null: true

      field :draft, DraftReadType, null: true, complexity: 100 do
        argument :key, String, required: true
        argument :sequence, GraphQL::Types::BigInt, required: false
      end
      field :drafts, DraftPageType, null: true do
        extras [:lookahead]
        argument :first, Int, required: false, default_value: 25, replace_null_with_default: true
        argument :after, String, required: false
        complexity ->(_context, arguments, child) { 100 + arguments[:first].clamp(1, 50) * (20 + child) }
      end

      field :bookmarks, BookmarkPageType, null: true do
        extras [:lookahead]
        argument :first, Int, required: false, default_value: 20, replace_null_with_default: true
        argument :after, String, required: false
        argument :search, String, required: false
        complexity ->(_context, arguments, child_complexity) do
          100 + arguments[:first].clamp(1, 20) * (20 + child_complexity)
        end
      end

      field :notifications, NotificationPageType, null: true do
        extras [:lookahead]
        argument :first, Int, required: false, default_value: 25, replace_null_with_default: true
        argument :after, String, required: false
        argument :filter, NotificationFilter, required: false
        complexity ->(_context, arguments, child_complexity) do
          100 + arguments[:first].clamp(1, 50) * (20 + child_complexity)
        end
      end

      field :topic, TopicType, null: true do
        argument :id, ID, required: true
      end

      field :topic_posts, PostPageType, null: true do
        argument :topic_id, ID, required: true
        argument :first, Int, required: false, default_value: 20, replace_null_with_default: true
        argument :after, String, required: false
        complexity ->(_context, arguments, child_complexity) do
          1 + arguments[:first].clamp(1, 50) * child_complexity
        end
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

      def draft(key:, sequence: nil)
        DraftLookup.new(request: context[:request]).call(key: key, sequence: sequence)
      end

      def drafts(first:, lookahead:, after: nil)
        fields = lookahead.selection(:nodes).selections.map { |selection| selection.field.method_sym }
        DraftList.new(request: context[:request]).call(first: first, after: after, fields: fields)
      end

      def bookmarks(first:, lookahead:, after: nil, search: nil)
        fields = lookahead.selection(:nodes).selections.map { |selection| selection.field.method_sym }
        Bookmarks.new(request: context[:request]).call(first: first, after: after, search: search, fields: fields)
      end

      def notifications(first:, lookahead:, after: nil, filter: nil)
        fields = lookahead.selection(:nodes).selections.map { |selection| selection.field.method_sym }
        Notifications.new(request: context[:request]).call(first: first, after: after, filter: filter, fields: fields)
      end

      def current_user
        context[:guardian].user.presence
      end

      def capabilities
        Extensions.capabilities
      end

      def topic(id:)
        dataloader.with(Loaders::RecordLoader, Topic).load(id)
      end

      def topic_posts(topic_id:, first:, after: nil)
        TopicPosts.new(guardian: context[:guardian]).call(
          topic_id: topic_id,
          first: first,
          after: after,
        )
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
