module DiscourseGraphQL
  module Chat
    module ThreadMessageProjection
      def select_graphql_messages(rows:, fields:)
        @graphql_messages = rows&.map do |serializer|
          ThreadFieldSelection.select(serializer: serializer, fields: fields)
        end
      end

      def messages
        @graphql_messages
      end
    end
  end
end
