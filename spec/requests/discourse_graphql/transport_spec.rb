require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user)
  let!(:api_key) { Fabricate(:api_key, user: user) }

  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }
  let(:identity_query) { "query { currentUser { id username } }" }

  describe "#execute" do
    it "supports the standard client schema discovery query" do
      post "/discourse-graphql/graphql",
           params: { query: GraphQL::Introspection::INTROSPECTION_QUERY },
           headers: headers

      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.dig("data", "__schema", "queryType", "name")).to eq("Query")
    end

    it "identifies the API actor without exposing private user attributes" do
      post "/discourse-graphql/graphql", params: { query: identity_query }, headers: headers

      expect(response.status).to eq(200)
      expect(response.parsed_body).to eq(
        "data" => { "currentUser" => { "id" => user.id.to_s, "username" => user.username } },
      )
    end

    it "rejects invalid and revoked API credentials" do
      post "/discourse-graphql/graphql",
           params: { query: identity_query },
           headers: { "Api-Key" => "invalid", "Api-Username" => user.username }

      expect(response.status).to eq(403)

      api_key.update!(revoked_at: Time.current)
      post "/discourse-graphql/graphql", params: { query: identity_query }, headers: headers

      expect(response.status).to eq(403)
      expect(response.body).not_to include(user.username)
    end

    it "keeps granular credentials restricted to their existing operations" do
      api_key.update!(
        scope_mode: :granular,
        api_key_scopes: [ApiKeyScope.new(resource: "topics", action: "read")],
      )

      post "/discourse-graphql/graphql", params: { query: identity_query }, headers: headers

      expect(response.status).to eq(403)
      expect(response.body).not_to include(user.username)
    end

    it "rejects malformed variables without leaking server diagnostics" do
      post "/discourse-graphql/graphql",
           params: { query: identity_query, variables: "{" },
           headers: headers

      expect(response.status).to eq(400)
      expect(response.parsed_body.fetch("errors").map { |error| error.dig("extensions", "code") }).to include("BAD_REQUEST")
      expect(response.parsed_body.to_s).not_to match(/backtrace|JSON::ParserError/)
    end

    it "executes the selected operation with JSON string variables" do
      query = <<~GRAPHQL
        query Identity { currentUser { username } }
        query Selected($includeUsername: Boolean!) {
          currentUser { id username @include(if: $includeUsername) }
        }
      GRAPHQL

      post "/discourse-graphql/graphql",
           params: {
             query: query,
             operationName: "Selected",
             variables: { includeUsername: false }.to_json,
           },
           headers: headers

      expect(response.status).to eq(200)
      expect(response.parsed_body).to eq("data" => { "currentUser" => { "id" => user.id.to_s } })
    end

    it "rejects request arrays instead of executing a hidden batch" do
      post "/discourse-graphql/graphql",
           params: [{ query: identity_query }, { query: identity_query }],
           headers: headers,
           as: :json

      expect(response.status).to eq(400)
    end

    it "allows anonymous public queries without inventing an identity" do
      get "/discourse-graphql/graphql", params: { query: identity_query }

      expect(response.status).to eq(200)
      expect(response.parsed_body).to eq("data" => { "currentUser" => nil })
    end

    it "keeps read credentials restricted to query requests through GET" do
      api_key.update!(
        scope_mode: :read_only,
        api_key_scopes: [ApiKeyScope.new(resource: "global", action: "read")],
      )

      get "/discourse-graphql/graphql", params: { query: identity_query }, headers: headers

      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("data", "currentUser", "id")).to eq(user.id.to_s)

      post "/discourse-graphql/graphql", params: { query: identity_query }, headers: headers

      expect(response.status).to eq(403)
    end

    it "rejects mutation documents sent through GET" do
      get "/discourse-graphql/graphql",
          params: { query: "mutation { __typename }" },
          headers: headers

      expect(response.status).to eq(400)
      expect(response.parsed_body.fetch("errors").map { |error| error.dig("extensions", "code") }).to include("BAD_REQUEST")
    end

    it "rejects an unavailable plugin endpoint" do
      SiteSetting.discourse_graphql_enabled = false

      post "/discourse-graphql/graphql", params: { query: identity_query }, headers: headers

      expect(response.status).to eq(404)
    end

    it "keeps authenticated responses out of shared caches" do
      post "/discourse-graphql/graphql", params: { query: identity_query }, headers: headers

      expect(response.status).to eq(200)
      expect(response.headers.fetch("Cache-Control")).to match(/private|no-store/)
    end

    context "with browser CSRF protection" do
      before do
        sign_in(user)
        ActionController::Base.allow_forgery_protection = true
      end

      after { ActionController::Base.allow_forgery_protection = false }

      it "rejects browser POST requests without a valid CSRF token" do
        post "/discourse-graphql/graphql", params: { query: identity_query }

        expect(response.status).to eq(403)
      end

      it "preserves the exemption for authenticated API credentials" do
        post "/discourse-graphql/graphql", params: { query: identity_query }, headers: headers

        expect(response.status).to eq(200)
        expect(response.parsed_body.dig("data", "currentUser", "id")).to eq(user.id.to_s)
      end
    end
  end
end
