module DiscourseGraphQL
  module Chat
    module MessageArrayPage
      def self.call(source:, kind:, context:, lookahead:, first:, after:, maximum_first:, scope:)
        raise Discourse::InvalidParameters unless first.between?(1, maximum_first)
        if source && (!scope["id"] || !scope["chat_channel_id"])
          raise Discourse::InvalidParameters if after
          if source.size > first && lookahead.selection(:page_info).selects?(:end_cursor)
            raise GraphQL::ExecutionError.new(
              I18n.t("discourse_graphql.errors.operation_failed"),
              extensions: { code: "UNAVAILABLE" },
            )
          end
        end
        NativeArrayPage.call(
          source: source,
          kind: kind,
          context: context,
          lookahead: lookahead,
          first: first,
          after: after,
          maximum_first: maximum_first,
          scope: scope,
        )
      end
    end
  end
end
