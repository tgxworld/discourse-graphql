module DiscourseGraphQL
  class TopicPosts
    def initialize(guardian:)
      @guardian = guardian
    end

    def call(topic_id:, first:, after: nil)
      raise Discourse::InvalidParameters unless first.between?(1, 50)

      topic_id = Topic.type_for_attribute("id").cast(topic_id)
      page = after.nil? ? 1 : cursor_page(cursor: after, topic_id: topic_id, first: first)
      view =
        TopicView.new(
          topic_id,
          @guardian.user,
          limit: first,
          page: page,
          include_suggested: false,
          include_related: false,
        )

      posts = view.posts.to_a
      ActiveRecord::Associations::Preloader.new(
        records: posts,
        associations: { topic: [:category, :shared_draft] },
      ).call
      nodes = posts.select { |post| view.guardian.can_see_post?(post) }
      cursor =
        if posts.present?
          verifier.generate(cursor_payload(topic_id: topic_id, first: first, page: page + 1))
        end

      {
        nodes: nodes,
        page_info: { end_cursor: cursor, has_next_page: view.next_page.present? },
      }
    end

    private

    def cursor_page(cursor:, topic_id:, first:)
      raise Discourse::InvalidParameters if cursor.bytesize > 4096

      payload = verifier.verified(cursor)
      if !payload.is_a?(Hash) || !payload["page"].is_a?(Integer) || payload["page"] < 1 ||
           payload != cursor_payload(topic_id: topic_id, first: first, page: payload["page"])
        raise Discourse::InvalidParameters
      end

      payload.fetch("page")
    end

    def cursor_payload(topic_id:, first:, page:)
      {
        "topic_id" => topic_id,
        "first" => first,
        "page" => page,
        "actor_id" => @guardian.user&.id,
        "site" => RailsMultisite::ConnectionManagement.current_db,
      }
    end

    def verifier
      Rails.application.message_verifier("discourse_graphql_topic_posts")
    end
  end
end
