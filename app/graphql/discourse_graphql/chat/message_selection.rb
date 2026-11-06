module DiscourseGraphQL
  module Chat
    module MessageSelection
      COLLECTION_FIELDS = %i[reactions mentioned_users uploads blocks].freeze
      private_constant :COLLECTION_FIELDS

      def self.select(serializer:, lookahead:)
        return serializer unless serializer.is_a?(ActiveModel::Serializer)
        serializer.extend(self)
        serializer.select_graphql_message_fields(lookahead)
        serializer
      end

      def select_graphql_message_fields(lookahead)
        @graphql_message_lookahead = lookahead
        fields = lookahead.selections.map { |selection| selection.field.method_sym }
        fields |= %i[id chat_channel_id] if (fields & COLLECTION_FIELDS).any?
        NativeFieldSelection.select(serializer: self, fields: fields)
      end

      def thread
        serializer = super
        return serializer unless serializer.is_a?(ActiveModel::Serializer)
        fields = @graphql_message_lookahead.selection(:thread).selections.map { |selection| selection.field.method_sym }
        NativeFieldSelection.select(serializer: serializer, fields: fields)
      end
    end
  end
end
