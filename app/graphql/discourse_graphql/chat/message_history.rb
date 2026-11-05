module DiscourseGraphQL
  module Chat
    class MessageHistory < ::Chat::Api::ChannelMessagesController
      include NativeRequest

      def call(channel_id:, last:, before: nil)
        raise Discourse::InvalidParameters unless last.between?(1, 50)

        @before_boundary = before.nil? ? nil : cursor_boundary(cursor: before, channel_id: channel_id, last: last)
        self.params = ActionController::Parameters.new(
          channel_id: channel_id,
          page_size: last,
          direction: "past",
          target_message_id: @before_boundary&.fetch(:message_id),
        )
        process(:index)
        result = NativeResponse.new(response)
        result.raise_error!
        payload = result.payload

        cursor =
          if @next_boundary
            verifier.generate(cursor_payload(channel_id: channel_id, last: last, **@next_boundary))
          end
        {
          nodes: payload.fetch("messages"),
          page_info: {
            start_cursor: cursor,
            has_previous_page: payload.fetch("meta").fetch("can_load_more_past"),
            end_cursor: nil,
            has_next_page: false,
          },
        }
      end

      private

      def render_serialized(object, serializer, options = nil)
        return super unless serializer == ::Chat::MessagesSerializer

        if @before_boundary && object.messages.last
          newest = object.messages.last
          ordering = [newest.created_at, newest.id] <=> [@before_boundary.fetch(:created_at), @before_boundary.fetch(:message_id)]
          raise Discourse::InvalidParameters if ordering >= 0
        end
        oldest = object.messages.first
        @next_boundary = { message_id: oldest.id, created_at: oldest.created_at } if oldest

        super(object, MessagePageSerializer, options)
      end

      def cursor_boundary(cursor:, channel_id:, last:)
        raise Discourse::InvalidParameters if cursor.bytesize > 4096

        payload = verifier.verified(cursor)
        if !payload.is_a?(Hash) || !payload["message_id"].is_a?(Integer) || payload["message_id"] < 1 ||
             !payload["created_at"].is_a?(String)
          raise Discourse::InvalidParameters
        end

        boundary = { message_id: payload.fetch("message_id"), created_at: Time.iso8601(payload.fetch("created_at")) }
        if payload != cursor_payload(channel_id: channel_id, last: last, **boundary)
          raise Discourse::InvalidParameters
        end
        boundary
      rescue ArgumentError
        raise Discourse::InvalidParameters
      end

      def cursor_payload(channel_id:, last:, message_id:, created_at:)
        {
          "channel_id" => channel_id,
          "last" => last,
          "message_id" => message_id,
          "created_at" => created_at.iso8601(6),
          "actor_id" => current_user&.id,
          "site" => RailsMultisite::ConnectionManagement.current_db,
        }
      end

      def verifier
        Rails.application.message_verifier("discourse_graphql_chat_history")
      end
    end
  end
end
