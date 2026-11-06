module DiscourseGraphQL
  class SearchQuery < ::SearchController
    def initialize(request:)
      super()
      set_request!(ActionDispatch::Request.new(request.env.dup))
      set_response!(ActionDispatch::Response.new)
      self.request.format = :json
    end

    def call(term:, page:)
      ensure_can_search

      if term.include?("\u0000") ||
           (
             term.length < SiteSetting.min_search_term_length && !::Search.min_length_bypass?(term)
           ) || page > ::SearchController::PAGE_LIMIT
        raise Discourse::InvalidParameters
      end

      limit = rate_limit_search
      raise limit if limit

      if site_overloaded?
        raise GraphQL::ExecutionError.new(
                I18n.t("search.extreme_load_error"),
                extensions: {
                  code: "UNAVAILABLE",
                },
              )
      end

      result =
        ::Search.new(
          term,
          guardian: guardian,
          type_filter: "topic",
          blurb_length: 300,
          page: [page, 1].max,
          search_type: :full_page,
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          session_id: pageview_session_id,
          user_id: current_user&.id,
        ).execute(readonly_mode: Discourse.readonly_mode?)

      raise Discourse::InvalidParameters if result.blank?

      result
    end
  end
end
