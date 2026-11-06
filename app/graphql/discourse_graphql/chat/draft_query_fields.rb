module DiscourseGraphQL
  module Chat
    module DraftQueryFields
      MAX_PAGE_SIZE = 20
      private_constant :MAX_PAGE_SIZE

      def self.included(type)
        type.field :current_user_chat_drafts, DraftPageType, null: true do
          extras [:lookahead]
          argument :first,
                   Integer,
                   required: false,
                   default_value: MAX_PAGE_SIZE,
                   replace_null_with_default: true
          argument :after, String, required: false
          complexity ->(_context, arguments, child) do
                       1000 + arguments[:first].clamp(1, MAX_PAGE_SIZE) * (20 + child)
                     end
        end
      end

      def self.capability
        {
          id: "chat.draftReading",
          available: Discourse.plugins_by_name.fetch("chat").enabled?,
          query_fields: ["currentUserChatDrafts"],
          mutation_fields: [],
        }
      end

      def current_user_chat_drafts(first:, lookahead:, after: nil)
        Extensions.ensure_enabled!("chat")
        raise Discourse::InvalidParameters unless first.between?(1, MAX_PAGE_SIZE)
        cache = context.namespace(:chat_draft_windows)
        key = [context[:guardian].user&.id, RailsMultisite::ConnectionManagement.current_db]
        source =
          cache.fetch(key) do
            cache[key] = CurrentUserDrafts.new(
              request: context[:request],
              request_method: "GET",
            ).call
          end
        NativeArrayPage.call(
          source: source,
          kind: "chat_drafts",
          context: context,
          lookahead: lookahead,
          first: first,
          after: after,
          maximum_first: MAX_PAGE_SIZE,
        )
      end
    end
  end
end
