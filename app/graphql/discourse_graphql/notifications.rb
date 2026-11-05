module DiscourseGraphQL
  class Notifications < ::NotificationsController
    include NativeRequest

    def self.requires_login_arg
      superclass.requires_login_arg
    end

    def call(first:, fields:, after: nil, filter: nil)
      raise Discourse::InvalidParameters unless first.between?(1, 50)
      @fields = fields
      @filter = filter
      offset = after.nil? ? 0 : cursor_offset(cursor: after, first: first)
      self.params = ActionController::Parameters.new(limit: first, offset: offset, filter: filter)
      process(:index)
      result = NativeResponse.new(response)
      result.raise_error!
      payload = result.payload
      has_next_page = offset + first < payload.fetch("total_rows_notifications")
      cursor = verifier.generate(cursor_payload(offset: offset + first, first: first)) if has_next_page
      {
        nodes: payload.fetch("notifications"),
        seen_notification_id: payload.fetch("seen_notification_id"),
        page_info: { end_cursor: cursor, has_next_page: has_next_page },
      }
    end

    private

    def notifications_path(options = {})
      Rails.application.routes.url_helpers.notifications_path(options)
    end

    def serialize_data(object, serializer, options = nil)
      return super unless serializer == ::NotificationSerializer

      super(object, serializer, NativeSerialization.options(options: options || {}, fields: @fields))
    end

    def cursor_offset(cursor:, first:)
      raise Discourse::InvalidParameters if cursor.bytesize > 4096

      payload = verifier.verified(cursor)
      if !payload.is_a?(Hash) || !payload["offset"].is_a?(Integer) || payload["offset"] < 0 ||
           payload != cursor_payload(offset: payload["offset"], first: first)
        raise Discourse::InvalidParameters
      end
      payload.fetch("offset")
    end

    def cursor_payload(offset:, first:)
      {
        "offset" => offset,
        "first" => first,
        "filter" => @filter,
        "actor_id" => current_user&.id,
        "site" => RailsMultisite::ConnectionManagement.current_db,
      }
    end

    def verifier
      Rails.application.message_verifier("discourse_graphql_notifications")
    end
  end
end
