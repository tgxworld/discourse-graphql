module DiscourseGraphQL
  class Bookmarks < ::UsersController
    include NativeRequest

    def call(first:, fields:, after: nil, search: nil)
      raise Discourse::InvalidParameters unless first.between?(1, 20)
      raise Discourse::InvalidParameters if search && search.size > 200
      @fields = fields
      @search = search
      page = after.nil? ? 0 : cursor_page(cursor: after, first: first)
      self.params =
        ActionController::Parameters.new(
          username: current_user&.username,
          limit: first,
          page: page,
          q: search,
        )
      process(:bookmarks)
      result = NativeResponse.new(response)
      result.raise_error!
      payload = result.payload.fetch("user_bookmark_list", result.payload)
      has_next_page = payload["more_bookmarks_url"].present?
      cursor = verifier.generate(cursor_payload(page: page + 1, first: first)) if has_next_page
      {
        nodes: payload.fetch("bookmarks"),
        page_info: {
          end_cursor: cursor,
          has_next_page: has_next_page,
        },
      }
    end

    private

    def serialize_data(object, serializer, options = nil)
      return super unless serializer == ::UserBookmarkListSerializer

      options =
        NativeSerialization.options(
          options: options || {},
          fields: %i[bookmarks more_bookmarks_url],
        )
      options = { root: "user_bookmark_list" }.merge(options).merge(bookmark_fields: @fields)
      super(object, BookmarkListSerializer, options)
    end

    def cursor_page(cursor:, first:)
      raise Discourse::InvalidParameters if cursor.bytesize > 4096

      payload = verifier.verified(cursor)
      if !payload.is_a?(Hash) || !payload["page"].is_a?(Integer) || payload["page"] < 0 ||
           payload != cursor_payload(page: payload["page"], first: first)
        raise Discourse::InvalidParameters
      end
      payload.fetch("page")
    end

    def cursor_payload(page:, first:)
      {
        "page" => page,
        "first" => first,
        "search" => @search,
        "actor_id" => current_user&.id,
        "site" => RailsMultisite::ConnectionManagement.current_db,
      }
    end

    def verifier
      Rails.application.message_verifier("discourse_graphql_bookmarks")
    end
  end
end
