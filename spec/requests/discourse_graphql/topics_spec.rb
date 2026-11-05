require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user)
  fab!(:topic)
  fab!(:private_group, :group)
  fab!(:private_category) { Fabricate(:private_category, group: private_group) }
  fab!(:private_topic) { Fabricate(:topic, category: private_category) }
  fab!(:message) { Fabricate(:private_message_topic, user: user) }

  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }

  describe "#execute" do
    it "reads public topics and permitted personal messages" do
      query = <<~GRAPHQL
        query {
          public: topic(id: "#{topic.id}") { id fancyTitle category { id } }
          personal: topic(id: "#{message.id}") { id fancyTitle category { id } }
        }
      GRAPHQL

      post "/discourse-graphql/graphql", params: { query: query }, headers: headers

      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.fetch("data")).to eq(
        "public" => {
          "id" => topic.id.to_s,
          "fancyTitle" => topic.fancy_title,
          "category" => {
            "id" => topic.category_id.to_s,
          },
        },
        "personal" => {
          "id" => message.id.to_s,
          "fancyTitle" => message.fancy_title,
          "category" => nil,
        },
      )
    end

    it "returns null for hidden and missing topics while preserving permitted siblings" do
      query = <<~GRAPHQL
        query {
          restricted: topic(id: "#{private_topic.id}") { id fancyTitle }
          missing: topic(id: "0") { id fancyTitle }
          currentUser { id }
        }
      GRAPHQL

      post "/discourse-graphql/graphql", params: { query: query }, headers: headers

      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.fetch("data")).to eq(
        "restricted" => nil,
        "missing" => nil,
        "currentUser" => {
          "id" => user.id.to_s,
        },
      )
      expect(response.body).not_to include(private_topic.title)
    end

    it "rechecks permission after personal message access is removed" do
      query = "query { topic(id: \"#{message.id}\") { id fancyTitle } }"

      post "/discourse-graphql/graphql", params: { query: query }, headers: headers
      expect(response.parsed_body.dig("data", "topic", "id")).to eq(message.id.to_s)

      message.topic_allowed_users.find_by!(user_id: user.id).destroy!
      post "/discourse-graphql/graphql", params: { query: query }, headers: headers

      expect(response.status).to eq(200)
      expect(response.parsed_body).to eq("data" => { "topic" => nil })
    end
  end
end
