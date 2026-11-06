module DiscourseGraphQL
  module Chat
    module QueryFields
      def self.included(type)
        type.field :chat_channels, ChannelPageType, null: true do
          extras [:lookahead]
          argument :first,
                   GraphQL::Types::Int,
                   required: false,
                   default_value: 25,
                   replace_null_with_default: true
          argument :after, GraphQL::Types::String, required: false
          argument :filter, GraphQL::Types::String, required: false
          complexity ->(_context, arguments, child_complexity) do
                       100 + arguments[:first].clamp(1, 50) * (20 + child_complexity)
                     end
        end
        type.field :chat_channel, ChannelType, null: true, complexity: 100 do
          extras [:lookahead]
          argument :id, GraphQL::Types::ID, required: true
        end
      end

      def self.capability
        {
          id: "chat.channelDiscovery",
          available: Discourse.plugins_by_name.fetch("chat").enabled?,
          query_fields: %w[chatChannels chatChannel],
          mutation_fields: [],
        }
      end

      def chat_channels(first:, after: nil, filter: nil, lookahead:)
        Extensions.ensure_enabled!("chat")

        fields =
          lookahead.selection(:nodes).selections.map { |selection| selection.field.method_sym }
        Channels.new(request: context[:request]).call(
          first: first,
          after: after,
          filter: filter,
          fields: fields,
        )
      end

      def chat_channel(id:, lookahead:)
        Extensions.ensure_enabled!("chat")
        fields = lookahead.selections.map { |selection| selection.field.method_sym }
        Channel.new(request: context[:request]).call(channel_id: id, fields: fields)
      end
    end
  end
end
