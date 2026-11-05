module DiscourseGraphQL
  module Analysis
    class Depth < GraphQL::Analysis::QueryDepth
      def result
        return if super <= 12

        GraphQL::AnalysisError.new(
          I18n.t("discourse_graphql.errors.query_too_deep"),
          extensions: {
            code: "QUERY_TOO_DEEP",
          },
        )
      end
    end
  end
end
