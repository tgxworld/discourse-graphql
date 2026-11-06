module DiscourseGraphQL
  module Chat
    class MessageType < Types::BaseObject
      graphql_name "ChatMessage"

      field :id, ID, null: false
      field :raw, String, null: true, hash_key: "message"
      field :cooked, String, null: true
      field :excerpt, String, null: true
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false, hash_key: "created_at"
      field :deleted_at, GraphQL::Types::ISO8601DateTime, null: true, hash_key: "deleted_at"
      field :deleted_by_id, ID, null: true, hash_key: "deleted_by_id"
      field :author, MessageAuthorType, null: true, hash_key: "user"
      field :thread_id, ID, null: true, hash_key: "thread_id"
      field :channel_id, ID, null: false, hash_key: "chat_channel_id"
      field :streaming, Boolean, null: false
      field :edited, Boolean, null: true, hash_key: "edited"
      field :pinned, Boolean, null: true, hash_key: "pinned"
      field :is_action, Boolean, null: true, hash_key: "is_action"
      field :thread_title, String, null: true, hash_key: "thread_title"
      field :available_flags, [String], null: true, hash_key: "available_flags", complexity: 10
      field :bookmark, MessageBookmarkType, null: true, hash_key: "bookmark"
      field :in_reply_to, ReplyPreviewType, null: true, hash_key: "in_reply_to"
      field :webhook, WebhookPresentationType, null: true, hash_key: "chat_webhook_event"
      field :thread, ThreadType, null: true, hash_key: "thread", complexity: 1000

      { mentioned_users: [MessageUserPageType, 10, 50], uploads: [MessageUploadPageType, 10, 20], blocks: [MessageBlockPageType, 5, 5] }.each do |name, (type, default, maximum)|
        field name, type, null: true do
          extras [:lookahead]
          argument :first, Integer, required: false, default_value: default, replace_null_with_default: true
          argument :after, String, required: false
          complexity ->(_context, arguments, child) do
                       base = name == :blocks ? 1000 : 10
                       base + arguments[:first].clamp(1, maximum) * (1 + child)
                     end
        end
      end
      field :reactions, ReactionPageType, null: true do
        extras [:lookahead]
        argument :first,
                 Integer,
                 required: false,
                 default_value: 30,
                 replace_null_with_default: true
        argument :after, String, required: false
        complexity ->(_context, arguments, child) { 100 + arguments[:first].clamp(1, 50) * child }
      end

      def mentioned_users(first:, lookahead:, after: nil)
        message_collection(name: "mentioned_users", maximum: 50, first: first, lookahead: lookahead, after: after)
      end

      def uploads(first:, lookahead:, after: nil)
        message_collection(name: "uploads", maximum: 20, first: first, lookahead: lookahead, after: after)
      end

      def blocks(first:, lookahead:, after: nil)
        page = message_collection(name: "blocks", maximum: 5, first: first, lookahead: lookahead, after: after)
        if page
          scope = object.slice("id", "chat_channel_id")
          page[:nodes] = page[:nodes].map do |node|
            node&.merge(graphql_message_scope: scope, graphql_block_source: node)
          end
        end
        page
      end

      def reactions(first:, lookahead:, after: nil)
        MessageArrayPage.call(
          source: object["reactions"],
          kind: "chat_message_reactions",
          context: context,
          lookahead: lookahead,
          first: first,
          after: after,
          maximum_first: 50,
          scope: object.slice("id", "chat_channel_id"),
        )
      end

      private

      def message_collection(name:, maximum:, first:, lookahead:, after:)
        MessageArrayPage.call(
          source: object[name],
          kind: "chat_message_#{name}",
          context: context,
          lookahead: lookahead,
          first: first,
          after: after,
          maximum_first: maximum,
          scope: object.slice("id", "chat_channel_id"),
        )
      end
    end
  end
end
