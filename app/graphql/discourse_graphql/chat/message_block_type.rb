module DiscourseGraphQL
  module Chat
    class MessageBlockType < Types::BaseObject
      graphql_name "ChatMessageBlock"

      field :type, String, null: true, hash_key: "type"
      field :title, String, null: true, hash_key: "title"
      field :cooked_title, String, null: true, hash_key: "cooked_title"
      field :cooked_question, String, null: true, hash_key: "cooked_question"
      field :cooked_status, String, null: true, hash_key: "cooked_status"
      field :cooked_error, String, null: true, hash_key: "cooked_error"
      field :show_description, Boolean, null: true, hash_key: "show_description"
      field :description_label, String, null: true, hash_key: "description_label"

      { elements: [BlockElementPageType, 10], parameters: [BlockParameterPageType, 50], changes: [BlockChangePageType, 20] }.each do |name, (type, maximum)|
        field name, type, null: true do
          extras [:lookahead]
          argument :first, Integer, required: false, default_value: 10, replace_null_with_default: true
          argument :after, String, required: false
          complexity ->(_context, arguments, child) { 10 + arguments[:first].clamp(1, maximum) * (1 + child) }
        end
      end

      def elements(first:, lookahead:, after: nil)
        collection(name: "elements", maximum: 10, first: first, lookahead: lookahead, after: after)
      end

      def parameters(first:, lookahead:, after: nil)
        collection(name: "parameters", maximum: 50, first: first, lookahead: lookahead, after: after)
      end

      def changes(first:, lookahead:, after: nil)
        collection(name: "changes", maximum: 20, first: first, lookahead: lookahead, after: after)
      end

      private

      def collection(name:, maximum:, first:, lookahead:, after:)
        scope = object.fetch(:graphql_message_scope)
        if after || lookahead.selection(:page_info).selects?(:end_cursor)
          source = object.fetch(:graphql_block_source)
          fingerprints = context.namespace(:chat_block_fingerprints).compare_by_identity
          fingerprint = fingerprints[source] ||= Digest::SHA256.hexdigest(JSON.generate(source))
          scope = scope.merge("block" => fingerprint)
        end
        MessageArrayPage.call(
          source: object[name],
          kind: "chat_block_#{name}",
          context: context,
          lookahead: lookahead,
          first: first,
          after: after,
          maximum_first: maximum,
          scope: scope,
        )
      end
    end
  end
end
