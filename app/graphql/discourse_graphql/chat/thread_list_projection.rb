module DiscourseGraphQL
  module Chat
    module ThreadListProjection
      def select_graphql_thread_nodes(serializers:, fields:)
        @graphql_native_thread_serializers = serializers
        @graphql_thread_node_fields = fields
      end

      def threads
        return nil if @graphql_native_thread_serializers.nil?
        natives =
          @graphql_native_thread_serializers.map do |native|
            ThreadFieldSelection.select(serializer: native, fields: @graphql_thread_node_fields)
          end
        if SiteSetting.enable_user_status
          originals =
            natives.filter_map do |native|
              native.object.original_message if native.include?(:original_message)
            end
          ActiveRecord::Associations::Preloader.new(
            records: originals,
            associations: [{ user: :user_option }, { user_mentions: { user: :user_option } }],
          ).call
        end
        natives
      end
    end
  end
end
