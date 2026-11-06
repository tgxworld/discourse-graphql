module DiscourseGraphQL
  module Chat
    class ReactionUsers < ::Chat::ChatController
      include NativeRequest

      def call(channel_id:, message_id:, first:, fields:, emoji: nil, after: nil)
        raise Discourse::InvalidParameters unless first.between?(1, 50)
        ReactionInputLimits.validate_emoji_size!(emoji)
        @fields = fields
        @cursor_context = {
          "channel_id" => channel_id,
          "message_id" => message_id,
          "first" => first,
          "emoji" => emoji,
          "actor_id" => current_user&.id,
          "site" => RailsMultisite::ConnectionManagement.current_db,
        }
        page = after.nil? ? 0 : cursor_page(after)
        self.params =
          ActionController::Parameters.new(
            chat_channel_id: channel_id,
            message_id: message_id,
            emoji: emoji,
            limit: first,
            page: page,
          )
        process(:message_reactions_users)
        result = NativeResponse.new(response)
        result.raise_error!
        nodes = result.payload.fetch("users")
        total = result.payload.fetch("total_rows")
        has_next_page = nodes.any? && page * first + nodes.size < total
        cursor = verifier.generate(@cursor_context.merge("page" => page + 1)) if has_next_page
        {
          nodes: nodes,
          total_count: total,
          page_info: {
            end_cursor: cursor,
            has_next_page: has_next_page,
          },
        }
      end

      private

      def serialize_data(object, serializer, options = nil)
        return super unless serializer == ::Chat::ReactionUserSerializer
        super(
          object,
          serializer,
          NativeSerialization.options(options: options || {}, fields: @fields),
        )
      end

      def cursor_page(cursor)
        raise Discourse::InvalidParameters if cursor.bytesize > 4096
        payload = verifier.verified(cursor)
        unless payload.is_a?(Hash) && payload["page"].is_a?(Integer) && payload["page"] >= 0 &&
                 payload.except("page") == @cursor_context
          raise Discourse::InvalidParameters
        end
        payload.fetch("page")
      end

      def verifier
        Rails.application.message_verifier("discourse_graphql_chat_reaction_users")
      end
    end
  end
end
