module DiscourseGraphQL
  class SiteSettingList < SiteSettingRequest
    def call(first:, names: nil, categories: nil, plugin: nil, after: nil)
      raise Discourse::InvalidParameters unless first.between?(1, 100)
      filters = { names: names, categories: categories, plugin: plugin }.compact
      @filters = filters
      @page_size = first
      prepare_native_action(parameters: filters, action: :index, path: "/admin/site_settings.json")
      offset = after.nil? ? 0 : cursor_offset(after)
      process(:index)
      result = NativeResponse.new(response)
      result.raise_error!
      settings = result.payload.fetch("site_settings")
      nodes = settings.slice(offset, first) || []
      has_next_page = offset + nodes.size < settings.size
      cursor = verifier.generate(cursor_payload(offset + nodes.size)) if has_next_page
      { nodes: nodes, page_info: { end_cursor: cursor, has_next_page: has_next_page } }
    end

    private

    def cursor_offset(cursor)
      raise Discourse::InvalidParameters if cursor.bytesize > 16_384
      payload = verifier.verified(cursor)
      if !payload.is_a?(Hash) || !payload["offset"].is_a?(Integer) || payload["offset"] < 0 ||
           payload != cursor_payload(payload["offset"])
        raise Discourse::InvalidParameters
      end
      payload.fetch("offset")
    end

    def cursor_payload(offset)
      {
        "offset" => offset,
        "first" => @page_size,
        "filters" => @filters.deep_stringify_keys,
        "actor_id" => current_user&.id,
        "site" => RailsMultisite::ConnectionManagement.current_db,
      }
    end

    def verifier
      Rails.application.message_verifier("discourse_graphql_site_settings")
    end
  end
end
