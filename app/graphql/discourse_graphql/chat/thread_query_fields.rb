module DiscourseGraphQL
  module Chat
    module ThreadQueryFields
      def self.included(type)
        type.field :chat_thread, ThreadType, null: true, complexity: 1000 do
          extras [:lookahead]
          argument :channel_id, GraphQL::Types::ID, required: true
          argument :thread_id, GraphQL::Types::ID, required: true
        end
      end

      def self.capability
        {
          id: "chat.threadLookup",
          available: Discourse.plugins_by_name.fetch("chat").enabled?,
          query_fields: ["chatThread"],
          mutation_fields: [],
        }
      end

      def chat_thread(channel_id:, thread_id:, lookahead:)
        Extensions.ensure_enabled!("chat")
        fields = lookahead.selections.map { |selection| selection.field.method_sym }
        ThreadLookup.new(request: context[:request], request_method: "GET").call(
          parameters: {
            channel_id: channel_id,
            thread_id: thread_id,
          },
          fields: fields,
        )
      end
    end
  end
end
