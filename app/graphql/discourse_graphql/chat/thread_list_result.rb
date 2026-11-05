module DiscourseGraphQL
  module Chat
    module ThreadListResult
      private

      def prepare_thread_page(kind:, first:, lookahead:, channel_id: nil, after: nil)
        raise Discourse::InvalidParameters unless first.between?(1, 10)
        @first = first
        @cursor_context = { "kind" => kind, "channel_id" => channel_id, "first" => first, "actor_id" => current_user&.id, "site" => RailsMultisite::ConnectionManagement.current_db }
        @offset = after.nil? ? 0 : cursor_offset(after)
        @node_fields = lookahead.selection(:nodes).selections.map { |selection| selection.field.method_sym }
        @list_fields = []
        @list_fields << :threads if lookahead.selects?(:nodes)
        @list_fields << :tracking if lookahead.selects?(:tracking)
        @cursor_selected = lookahead.selection(:page_info).selects?(:end_cursor)
        self.params = ActionController::Parameters.new(limit: first, offset: @offset)
        params[:channel_id] = channel_id unless channel_id.nil?
      end

      def thread_page
        result = NativeResponse.new(response)
        result.raise_error!
        nodes = result.payload["threads"]
        count = @thread_count || nodes&.size
        if count
          has_next_page = count == @first
          cursor = verifier.generate(@cursor_context.merge("offset" => @offset + @first)) if has_next_page && @cursor_selected
          page_info = { end_cursor: cursor, has_next_page: has_next_page }
        end
        tracking = result.payload["tracking"]&.map { |thread_id, value| value.merge("thread_id" => thread_id) }
        { nodes: nodes, tracking: tracking, page_info: page_info }
      end

      def serialize_data(object, serializer, options = nil)
        return super unless serializer == ::Chat::ThreadListSerializer
        native = serializer.new(object, { scope: guardian }.merge(options || {}))
        rows = native.threads if native.include?(:threads)
        @thread_count = rows&.size
        native.extend(ThreadListProjection)
        native.select_graphql_thread_nodes(serializers: rows, fields: @node_fields)
        ThreadFieldSelection.select(serializer: native, fields: @list_fields).as_json
      end

      def cursor_offset(cursor)
        raise Discourse::InvalidParameters if cursor.bytesize > 4096
        payload = verifier.verified(cursor)
        unless payload.is_a?(Hash) && payload["offset"].is_a?(Integer) && payload["offset"] >= 0 && payload.except("offset") == @cursor_context
          raise Discourse::InvalidParameters
        end
        payload.fetch("offset")
      end

      def verifier
        Rails.application.message_verifier("discourse_graphql_chat_thread_lists")
      end
    end
  end
end
