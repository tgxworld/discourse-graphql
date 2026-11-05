module DiscourseGraphQL
  module Chat
    module HistoryQueryFields
      def self.included(type)
        type.field :chat_messages, MessagePageType, null: true do
          extras [:lookahead]
          argument :channel_id, GraphQL::Types::ID, required: true
          argument :last, GraphQL::Types::Int, required: false, default_value: 25, replace_null_with_default: true
          argument :before, GraphQL::Types::String, required: false
          complexity ->(_context, arguments, child_complexity) do
            100 + arguments[:last].clamp(1, 50) * (20 + child_complexity)
          end
        end
      end

      def self.capability
        {
          id: "chat.messageHistory",
          available: Discourse.plugins_by_name.fetch("chat").enabled?,
          query_fields: ["chatMessages"],
          mutation_fields: [],
        }
      end

      def chat_messages(channel_id:, last:, lookahead:, before: nil)
        Extensions.ensure_enabled!("chat")
        fields = lookahead.selection(:nodes).selections.map { |selection| selection.field.method_sym }
        MessageHistory.new(request: context[:request]).call(channel_id: channel_id, last: last, before: before, fields: fields)
      end
    end
  end
end
