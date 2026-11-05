module DiscourseGraphQL
  module Analysis
    class Complexity < GraphQL::Analysis::QueryComplexity
      def result
        return if super <= 10_000

        GraphQL::AnalysisError.new(
          I18n.t("discourse_graphql.errors.query_too_complex"),
          extensions: {
            code: "QUERY_TOO_COMPLEX",
          },
        )
      end
    end
  end
end
