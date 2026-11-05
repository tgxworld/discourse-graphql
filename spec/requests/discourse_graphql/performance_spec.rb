require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user)
  fab!(:topics) do
    Array.new(50) { Fabricate(:topic, category: Fabricate(:category), user: Fabricate(:user)) }
  end

  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }
  let(:query) { <<~GRAPHQL }
      query Topics($limit: Int!) {
        latestTopics(limit: $limit) {
          id
          category { id name }
          author { id username }
        }
      }
    GRAPHQL

  describe "#execute" do
    it "batches permission checks for distinct personal messages" do
      messages = Fabricate.times(50, :private_message_topic, user: user)
      query_counts =
        [1, 50].map do |limit|
          selections =
            messages
              .first(limit)
              .map do |message|
                "topic#{message.id}: topic(id: \"#{message.id}\") { id fancyTitle }"
              end

          queries =
            track_sql_queries do
              post "/discourse-graphql/graphql",
                   params: {
                     query: "query { #{selections.join(" ")} }",
                   },
                   headers: headers
            end

          expect(response.status).to eq(200)
          expect(response.parsed_body["errors"]).to be_blank
          expect(
            response.parsed_body.fetch("data").values.map { |entry| entry.fetch("id") },
          ).to match_array(messages.first(limit).map { |message| message.id.to_s })
          queries.size
        end

      expect(query_counts[1]).to be <= query_counts[0] + 2
    end

    it "bounds database query growth for 50 topics with distinct categories and authors" do
      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               limit: 1,
             },
           },
           headers: headers,
           as: :json

      query_counts =
        [1, 50].map do |limit|
          queries =
            track_sql_queries do
              post "/discourse-graphql/graphql",
                   params: {
                     query: query,
                     variables: {
                       limit: limit,
                     },
                   },
                   headers: headers,
                   as: :json
            end

          expect(response.status).to eq(200)
          expect(response.parsed_body["errors"]).to be_blank
          expect(response.parsed_body.fetch("data").fetch("latestTopics").size).to eq(limit)
          queries.size
        end

      expect(query_counts[1]).to be <= query_counts[0] + 2
    end
  end
end
