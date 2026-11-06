module DiscourseGraphQL
  module Chat
    module ThreadMutationFields
      def self.included(type)
        type.field :create_chat_thread, ThreadCreationPayloadType, null: true, complexity: 1000 do
          extras [:lookahead]
          argument :input, ThreadCreateInput, required: true
        end
      end

      def self.capability
        {
          id: "chat.threadCreation",
          available: Discourse.plugins_by_name.fetch("chat").enabled?,
          query_fields: [],
          mutation_fields: ["createChatThread"],
        }
      end

      def create_chat_thread(input:, lookahead:)
        Extensions.ensure_enabled!("chat")
        context.dataloader.clear_cache
        fields =
          lookahead.selection(:thread).selections.map { |selection| selection.field.method_sym }
        ThreadCreation.new(request: context[:request], request_method: "POST").call(
          parameters: input.to_h,
          fields: fields,
        )
      ensure
        context.dataloader.clear_cache
      end
    end
  end
end
