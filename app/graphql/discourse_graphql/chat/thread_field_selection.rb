module DiscourseGraphQL
  module Chat
    module ThreadFieldSelection
      def self.select(serializer:, fields:)
        serializer.extend(self)
        serializer.select_graphql_fields(fields)
        serializer
      end

      def select_graphql_fields(fields)
        @graphql_selected_thread_fields = fields
      end

      def include?(name)
        @graphql_selected_thread_fields.include?(name) && super
      end
    end
  end
end
