require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user)
  fab!(:public_category, :category)
  fab!(:private_group, :group)
  fab!(:private_category) { Fabricate(:private_category, group: private_group) }
  fab!(:private_topic) { Fabricate(:topic, category: private_category) }
  fab!(:private_post) { Fabricate(:post, topic: private_topic) }

  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }

  describe "#execute" do
    it "checks nested access when category activity references a now restricted topic" do
      public_category.update!(latest_topic_id: private_topic.id, latest_post_id: private_post.id)
      query = <<~GRAPHQL
        query {
          categories {
            id
            latestTopic { id fancyTitle }
            latestPost { id cooked }
          }
        }
      GRAPHQL

      post "/discourse-graphql/graphql", params: { query: query }, headers: headers

      expect(response.status).to eq(200)
      category =
        response
          .parsed_body
          .fetch("data")
          .fetch("categories")
          .find { |entry| entry.fetch("id") == public_category.id.to_s }
      expect(category).to eq(
        "id" => public_category.id.to_s,
        "latestTopic" => nil,
        "latestPost" => nil,
      )
      expect(response.body).not_to include(private_topic.title, private_post.cooked)
    end
  end
end
