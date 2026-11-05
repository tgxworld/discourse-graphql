module DiscourseGraphQL
  module Chat
    class MessagePageSerializer < ::Chat::MessagesSerializer
      def messages
        declared_fields = MessageType.fields.values.map(&:method_sym)
        super.map do |serializer|
          fields = declared_fields
          fields &= Array(serializer.options[:only]) if serializer.options.key?(:only)
          serializer.class.new(serializer.object, serializer.options.merge(only: fields))
        end
      end

      def include_tracking?
        false
      end
    end
  end
end
