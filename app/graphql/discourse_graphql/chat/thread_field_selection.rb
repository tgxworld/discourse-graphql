module DiscourseGraphQL
  module Chat
    module ThreadFieldSelection
      def include?(name)
        options.fetch(:graphql_thread_fields).include?(name) && super
      end
    end
  end
end
