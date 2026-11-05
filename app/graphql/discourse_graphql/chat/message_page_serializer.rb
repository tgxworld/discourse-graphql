module DiscourseGraphQL
  module Chat
    class MessagePageSerializer < ::Chat::MessagesSerializer
      def messages
        declared_fields =
          options.fetch(:graphql_message_fields) & MessageType.fields.values.map(&:method_sym)
        super.map do |serializer|
          serializer.class.new(
            serializer.object,
            NativeSerialization.options(options: serializer.options, fields: declared_fields),
          )
        end
      end

      def include_tracking?
        false
      end
    end
  end
end
