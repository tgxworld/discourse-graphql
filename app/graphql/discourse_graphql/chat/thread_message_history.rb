module DiscourseGraphQL
  module Chat
    class ThreadMessageHistory < ::Chat::Api::ChannelThreadMessagesController
      include NativeRequest

      def call(channel_id:, thread_id:, last:, lookahead:, before: nil)
        raise Discourse::InvalidParameters unless last.between?(1, 50)
        @cursor_context = {
          "channel_id" => channel_id,
          "thread_id" => thread_id,
          "last" => last,
          "actor_id" => current_user&.id,
          "site" => RailsMultisite::ConnectionManagement.current_db,
        }
        @before_boundary = before.nil? ? nil : cursor_boundary(before)
        @message_fields = lookahead.selection(:nodes).selections.map { |selection| selection.field.method_sym }
        @message_fields |= %i[id chat_channel_id] if @message_fields.include?(:reactions)
        @page_fields = []
        @page_fields << :messages if lookahead.selects?(:nodes)
        @page_fields << :meta if lookahead.selects?(:page_info)
        self.params = ActionController::Parameters.new(
          channel_id: channel_id,
          thread_id: thread_id,
          page_size: last,
          direction: "past",
          fetch_from_last_message: @before_boundary.nil?,
          target_message_id: @before_boundary&.fetch(:message_id),
        )
        process(:index)
        result = NativeResponse.new(response)
        result.raise_error!
        payload = result.payload
        more = payload.dig("meta", "can_load_more_past")
        if @messages_available && !more.nil? && (!more || @next_boundary)
          cursor = verifier.generate(@cursor_context.merge(@next_boundary)) if @next_boundary
          page_info = {
            start_cursor: cursor,
            has_previous_page: more,
            end_cursor: nil,
            has_next_page: false,
          }
        end
        { nodes: payload["messages"], page_info: page_info }
      end

      private

      def serialize_data(object, serializer, options = nil)
        return super unless serializer == ::Chat::MessagesSerializer
        native = serializer.new(object, { scope: guardian }.merge(options || {}))
        @messages_available = native.include?(:messages)
        rows = native.messages if @messages_available
        if rows.present? && rows.all? { |row| row.include?(:id) && row.include?(:created_at) }
          if @before_boundary
            boundary = [@before_boundary.fetch(:created_at), @before_boundary.fetch(:message_id)]
            if rows.any? { |row| ([row.object.created_at, row.object.id] <=> boundary) >= 0 }
              raise Discourse::InvalidParameters
            end
          end
          oldest = rows.first
          if oldest.id == oldest.object.id
            @next_boundary = { "message_id" => oldest.id, "created_at" => oldest.object.created_at.iso8601(6) }
          end
        end
        native.extend(ThreadMessageProjection)
        native.select_graphql_messages(rows: @page_fields.include?(:messages) ? rows : nil, fields: @message_fields)
        ThreadFieldSelection.select(serializer: native, fields: @page_fields).as_json
      end

      def cursor_boundary(cursor)
        raise Discourse::InvalidParameters if cursor.bytesize > 4096
        payload = verifier.verified(cursor)
        unless payload.is_a?(Hash) && payload["message_id"].is_a?(Integer) && payload["message_id"] > 0 &&
                 payload["created_at"].is_a?(String) && payload.except("message_id", "created_at") == @cursor_context
          raise Discourse::InvalidParameters
        end
        { message_id: payload.fetch("message_id"), created_at: Time.iso8601(payload.fetch("created_at")) }
      rescue ArgumentError
        raise Discourse::InvalidParameters
      end

      def verifier
        Rails.application.message_verifier("discourse_graphql_chat_thread_history")
      end
    end
  end
end
