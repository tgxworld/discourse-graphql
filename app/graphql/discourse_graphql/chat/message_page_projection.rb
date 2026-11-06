module DiscourseGraphQL
  module Chat
    module MessagePageProjection
      def select_graphql_messages(rows:, lookahead:)
        @graphql_messages =
          rows&.map do |serializer|
            MessageSelection.select(serializer: serializer, lookahead: lookahead)
          end
      end

      def messages
        @graphql_messages
      end
    end
  end
end
