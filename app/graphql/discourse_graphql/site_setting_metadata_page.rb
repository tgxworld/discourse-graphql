module DiscourseGraphQL
  class SiteSettingMetadataPage
    def self.call(source:, kind:, context:, lookahead:, first:, after: nil)
      raise Discourse::InvalidParameters unless first.between?(1, 100)
      if source.nil?
        raise Discourse::InvalidParameters if after
        return nil
      end
      raise Discourse::InvalidParameters unless source.is_a?(Array) || source.is_a?(Hash)

      cache = context.namespace(:site_setting_metadata_collections).compare_by_identity
      collection = cache[source] ||= {}
      cursor_selected = lookahead.selection(:page_info).selects?(:end_cursor)
      if after || cursor_selected
        digest = collection[:digest] ||= Digest::SHA256.hexdigest(JSON.generate(source))
        binding = { "kind" => kind, "digest" => digest, "first" => first, "actor_id" => context[:guardian].user.id, "site" => RailsMultisite::ConnectionManagement.current_db }
        verifier = Rails.application.message_verifier("discourse_graphql_setting_metadata")
      end
      offset = 0
      if after
        raise Discourse::InvalidParameters if after.bytesize > 16384
        payload = verifier.verified(after)
        unless payload.is_a?(Hash) && payload["offset"].is_a?(Integer) && payload["offset"].between?(0, source.size) && payload.except("offset") == binding
          raise Discourse::InvalidParameters
        end
        offset = payload.fetch("offset")
      end
      nodes = []
      if lookahead.selects?(:nodes)
        if source.is_a?(Hash)
          keys = collection[:keys] ||= source.keys
          nodes = (keys.slice(offset, first) || []).map { |name| [name, source.fetch(name)] }
        else
          nodes = source.slice(offset, first) || []
        end
      end
      has_next_page = offset + first < source.size
      cursor = verifier.generate(binding.merge("offset" => offset + first)) if has_next_page && cursor_selected
      { nodes: nodes, total_count: source.size, page_info: { end_cursor: cursor, has_next_page: has_next_page } }
    end
  end
end
