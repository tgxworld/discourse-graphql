module DiscourseGraphQL
  module Chat
    class Channels < ::Chat::Api::ChannelsController
      include NativeRequest

      def call(first:, fields:, after: nil, filter: nil)
        raise Discourse::InvalidParameters unless first.between?(1, 50)
        @fields = fields

        offset = after.nil? ? 0 : cursor_offset(cursor: after, first: first, filter: filter)
        self.params = ActionController::Parameters.new(limit: first, offset: offset, filter: filter)
        process(:index)
        result = NativeResponse.new(response)
        result.raise_error!
        payload = result.payload

        nodes = payload.fetch("channels")
        has_next_page = nodes.size == first
        cursor =
          if has_next_page
            verifier.generate(cursor_payload(offset: offset + first, first: first, filter: filter))
          end

        { nodes: nodes, page_info: { end_cursor: cursor, has_next_page: has_next_page } }
      end

      private

      def render(*arguments, &block)
        options = arguments.first
        if action_name == "index" && options.is_a?(Hash) && options[:json].is_a?(Array) &&
             options[:json].all? { |serializer| serializer.is_a?(::Chat::ChannelSerializer) }
          nodes =
            options[:json].map do |serializer|
              serializer.class.new(
                serializer.object,
                NativeSerialization.options(options: serializer.options, fields: @fields),
              )
            end
          arguments[0] = options.merge(json: nodes)
        end

        super(*arguments, &block)
      end

      def cursor_offset(cursor:, first:, filter:)
        raise Discourse::InvalidParameters if cursor.bytesize > 4096

        payload = verifier.verified(cursor)
        if !payload.is_a?(Hash) || !payload["offset"].is_a?(Integer) || payload["offset"] < 0 ||
             payload != cursor_payload(offset: payload["offset"], first: first, filter: filter)
          raise Discourse::InvalidParameters
        end

        payload.fetch("offset")
      end

      def cursor_payload(offset:, first:, filter:)
        {
          "offset" => offset,
          "first" => first,
          "filter" => filter,
          "actor_id" => current_user&.id,
          "site" => RailsMultisite::ConnectionManagement.current_db,
        }
      end

      def verifier
        Rails.application.message_verifier("discourse_graphql_chat_channels")
      end
    end
  end
end
