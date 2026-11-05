require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user)
  fab!(:public_post) do
    with_search_indexer_enabled { Fabricate(:post, raw: "A nebula observation from this community") }
  end
  fab!(:private_group, :group)
  fab!(:private_category) { Fabricate(:private_category, group: private_group) }
  fab!(:private_post) do
    with_search_indexer_enabled do
      Fabricate(
        :post,
        topic: Fabricate(:topic, category: private_category),
        raw: "A private nebula observation",
      )
    end
  end

  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }
  let(:query) do
    <<~GRAPHQL
      query Search($term: String!, $page: Int) {
        search(term: $term, page: $page) {
          id
          blurb
          username
          topic { id category { id } }
        }
      }
    GRAPHQL
  end

  describe "#execute" do
    it "returns permitted search results and records the existing search side effects" do
      SiteSetting.log_search_queries = true
      events =
        DiscourseEvent.track_events(:user_search) do
          post "/discourse-graphql/graphql",
               params: { query: query, variables: { term: "nebula", page: 1 } },
               headers: headers.merge("User-Agent" => "GraphQL search contract"),
               as: :json
        end

      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      results = response.parsed_body.fetch("data").fetch("search")
      expect(results.map { |entry| entry.fetch("id") }).to eq([public_post.id.to_s])
      expect(results.first.fetch("blurb")).to include("nebula")
      expect(results.first.fetch("username")).to eq(public_post.user.username)
      expect(response.body).not_to include(private_post.raw, private_category.name)
      expect(events.map { |event| event.fetch(:event_name) }).to eq([:user_search])
      search_log = SearchLog.find_by!(user_id: user.id, term: "nebula")
      expect(search_log.search_type).to eq(SearchLog.search_types[:full_page])
      expect(search_log.user_agent).to eq("GraphQL search contract")
    end

    it "rejects invalid search inputs with a stable error" do
      ["\u0000nebula", "a"].each do |term|
        post "/discourse-graphql/graphql",
             params: { query: query, variables: { term: term, page: 1 } },
             headers: headers,
             as: :json

        expect(response.status).to eq(200)
        expect(response.parsed_body.fetch("errors").map { |error| error.dig("extensions", "code") }).to include("BAD_USER_INPUT")
        expect(response.parsed_body.dig("data", "search")).to be_nil
      end

      post "/discourse-graphql/graphql",
           params: { query: query, variables: { term: "nebula", page: 11 } },
           headers: headers,
           as: :json

      expect(response.status).to eq(200)
      expect(response.parsed_body.fetch("errors").map { |error| error.dig("extensions", "code") }).to include("BAD_USER_INPUT")
    end

    it "preserves the existing anonymous search restriction" do
      SiteSetting.allow_anonymous_search = false

      get "/discourse-graphql/graphql",
          params: { query: query, variables: { term: "nebula" }.to_json }

      expect(response.status).to eq(200)
      expect(response.parsed_body.fetch("errors").map { |error| error.dig("extensions", "code") }).to include("UNAUTHENTICATED")
      expect(response.parsed_body.dig("data", "search")).to be_nil
    end

    it "shares the native search allowance across transports and aliases" do
      RateLimiter.enable
      SiteSetting.rate_limit_search_user = 1

      get "/search.json", params: { q: "nebula" }, headers: headers
      expect(response.status).to eq(200)

      post "/discourse-graphql/graphql",
           params: {
             query: 'query { first: search(term: "nebula") { id } second: search(term: "nebula") { id } }',
           },
           headers: headers

      expect(response.status).to eq(200)
      errors = response.parsed_body.fetch("errors")
      expect(errors.map { |error| error.dig("extensions", "code") }).to eq(["RATE_LIMITED", "RATE_LIMITED"])
      expect(errors.map { |error| error.dig("extensions", "retryAfterSeconds") }).to all(be > 0)
      expect(response.parsed_body.fetch("data")).to eq("first" => nil, "second" => nil)
    end

    it "rejects overloaded searches before recording a search" do
      global_setting :disable_search_queue_threshold, 0.2
      freeze_time

      expect do
        post "/discourse-graphql/graphql",
             params: { query: query, variables: { term: "nebula" } },
             headers: headers.merge("HTTP_X_REQUEST_START" => "t=#{1.second.ago.to_f}"),
             as: :json
      end.not_to change { SearchLog.where(user_id: user.id).count }

      expect(response.status).to eq(200)
      expect(response.parsed_body.fetch("errors").map { |error| error.dig("extensions", "code") }).to include("UNAVAILABLE")
      expect(response.parsed_body.dig("data", "search")).to be_nil
    end
  end
end
