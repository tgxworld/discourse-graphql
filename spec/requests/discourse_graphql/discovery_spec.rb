require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user)
  let!(:api_key) { Fabricate(:api_key, user: user) }
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category, user: user) }
  fab!(:private_group, :group)
  fab!(:private_category) { Fabricate(:private_category, group: private_group) }
  fab!(:private_topic) { Fabricate(:topic, category: private_category) }

  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }

  describe "#execute" do
    it "returns public categories and topic associations without revealing restricted content" do
      query = <<~GRAPHQL
        query {
          categories { id name }
          latestTopics {
            id
            fancyTitle
            category { id name }
            author { id username }
          }
        }
      GRAPHQL

      post "/discourse-graphql/graphql", params: { query: query }, headers: headers

      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      data = response.parsed_body.fetch("data")
      expect(data.fetch("categories").map { |entry| entry.fetch("id") }).to include(category.id.to_s)
      expect(data.fetch("latestTopics")).to include(
        "id" => topic.id.to_s,
        "fancyTitle" => topic.fancy_title,
        "category" => { "id" => category.id.to_s, "name" => category.name },
        "author" => { "id" => user.id.to_s, "username" => user.username },
      )
      expect(response.body).not_to include(private_category.name, private_topic.title)
    end

    it "rejects oversized pages before returning content" do
      query = "query { latestTopics(limit: 51) { id } }"

      post "/discourse-graphql/graphql", params: { query: query }, headers: headers

      expect(response.status).to eq(200)
      expect(response.parsed_body.fetch("errors").map { |error| error.dig("extensions", "code") }).to include("BAD_USER_INPUT")
      expect(response.parsed_body["data"]).to be_blank
    end

    it "supports bounded pages and an empty page at the end" do
      Fabricate(:topic, category: category, user: user)
      query = <<~GRAPHQL
        query Page($page: Int!) {
          latestTopics(page: $page, limit: 1, categoryId: #{category.id}) { id }
        }
      GRAPHQL

      pages =
        3.times.map do |page|
          post "/discourse-graphql/graphql",
               params: { query: query, variables: { page: page }, operationName: "Page" },
               headers: headers,
               as: :json

          expect(response.status).to eq(200)
          expect(response.parsed_body["errors"]).to be_blank
          response.parsed_body.fetch("data").fetch("latestTopics").map { |entry| entry.fetch("id") }
        end

      expect(pages[0].size).to eq(1)
      expect(pages[1].size).to eq(1)
      expect(pages[0]).not_to eq(pages[1])
      expect(pages[2]).to eq([])
    end

    it "rejects repeated expensive selections before loading their results" do
      selections =
        200.times.map { |index| "topics#{index}: latestTopics(limit: 50) { id fancyTitle }" }

      baseline_queries =
        track_sql_queries do
          post "/discourse-graphql/graphql",
               params: { query: "query { __typename }" },
               headers: headers
          expect(response.status).to eq(200)
          expect(response.parsed_body["errors"]).to be_blank
        end

      rejected_queries =
        track_sql_queries do
          post "/discourse-graphql/graphql",
               params: { query: "query { #{selections.join(" ")} }" },
               headers: headers
        end

      expect(response.status).to eq(200)
      expect(response.parsed_body.fetch("errors").map { |error| error.dig("extensions", "code") }).to include("QUERY_TOO_COMPLEX")
      expect(response.parsed_body["data"]).to be_blank
      expect(rejected_queries.size).to be <= baseline_queries.size
    end

    it "keeps negative page sizes from cancelling other selections in the query cost" do
      selections =
        200.times.map { |index| "topics#{index}: latestTopics(limit: 50) { id fancyTitle }" }
      selections << "invalid: latestTopics(limit: -1000000) { id fancyTitle }"

      post "/discourse-graphql/graphql",
           params: { query: "query { #{selections.join(" ")} }" },
           headers: headers

      expect(response.status).to eq(200)
      expect(response.parsed_body.fetch("errors").map { |error| error.dig("extensions", "code") }).to include("QUERY_TOO_COMPLEX")
      expect(response.parsed_body["data"]).to be_blank
    end

    it "uses the default page and size when optional page arguments are null" do
      post "/discourse-graphql/graphql",
           params: { query: "query { latestTopics(page: null, limit: null) { id } }" },
           headers: headers

      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.fetch("data").fetch("latestTopics")).to include("id" => topic.id.to_s)
    end
  end
end
