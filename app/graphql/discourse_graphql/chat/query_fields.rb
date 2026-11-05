module DiscourseGraphQL
  module Chat
    module QueryFields
      def self.included(type)
        type.field :chat_channels, ChannelPageType, null: true do
          argument :first, GraphQL::Types::Int, required: false, default_value: 25, replace_null_with_default: true
          argument :after, GraphQL::Types::String, required: false
          argument :filter, GraphQL::Types::String, required: false
          complexity ->(_context, arguments, child_complexity) do
            100 + arguments[:first].clamp(1, 50) * (20 + child_complexity)
          end
        end
      end

      def self.capability
        {
          id: "chat.channelDiscovery",
          available: Discourse.plugins_by_name.fetch("chat").enabled?,
          query_fields: ["chatChannels"],
          mutation_fields: [],
        }
      end

      def chat_channels(first:, after: nil, filter: nil)
        Extensions.ensure_enabled!("chat")

        Channels.new(request: context[:request]).call(first: first, after: after, filter: filter)
      end
    end
  end
end
