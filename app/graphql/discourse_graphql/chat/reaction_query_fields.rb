module DiscourseGraphQL
  module Chat
    module ReactionQueryFields
      def self.included(type)
        type.field :chat_reaction_users, ReactionUserPageType, null: true do
          extras [:lookahead]
          argument :channel_id, GraphQL::Types::ID, required: true
          argument :message_id, GraphQL::Types::ID, required: true
          argument :emoji, String, required: false
          argument :first, Integer, required: false, default_value: 25, replace_null_with_default: true
          argument :after, String, required: false
          complexity ->(_context, arguments, child) { 1000 + arguments[:first].clamp(1, 50) * (5 + child) }
        end
      end

      def self.capability
        { id: "chat.reactionUsers", available: Discourse.plugins_by_name.fetch("chat").enabled?, query_fields: ["chatReactionUsers"], mutation_fields: [] }
      end

      def chat_reaction_users(channel_id:, message_id:, first:, lookahead:, emoji: nil, after: nil)
        Extensions.ensure_enabled!("chat")
        fields = lookahead.selection(:nodes).selections.map { |selection| selection.field.method_sym }
        ReactionUsers.new(request: context[:request], request_method: "GET").call(channel_id: channel_id, message_id: message_id, first: first, emoji: emoji, after: after, fields: fields)
      end
    end
  end
end
