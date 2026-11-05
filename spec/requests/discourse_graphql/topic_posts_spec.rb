require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user)
  fab!(:topic)
  fab!(:first_post) { Fabricate(:post, topic: topic, post_number: 1) }
  fab!(:second_post) { Fabricate(:post, topic: topic, post_number: 2) }
  fab!(:third_post) { Fabricate(:post, topic: topic, post_number: 3) }

  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }
  let(:query) { <<~GRAPHQL }
      query Posts($topicId: ID!, $first: Int, $after: String) {
        topicPosts(topicId: $topicId, first: $first, after: $after) {
          nodes { id raw cooked postNumber author { id username } }
          pageInfo { endCursor hasNextPage }
        }
      }
    GRAPHQL

  describe "#execute" do
    it "reads a discussion through bounded pages with an empty terminal page" do
      cursor = nil
      pages =
        3.times.map do
          post "/discourse-graphql/graphql",
               params: {
                 query: query,
                 variables: {
                   topicId: topic.id,
                   first: 2,
                   after: cursor,
                 },
               },
               headers: headers,
               as: :json

          expect(response.status).to eq(200)
          expect(response.parsed_body["errors"]).to be_blank
          page = response.parsed_body.fetch("data").fetch("topicPosts")
          cursor = page.fetch("pageInfo").fetch("endCursor")
          page
        end

      expect(pages.map { |page| page.fetch("nodes").map { |entry| entry.fetch("id") } }).to eq(
        [[first_post.id.to_s, second_post.id.to_s], [third_post.id.to_s], []],
      )
      expect(pages.map { |page| page.dig("pageInfo", "hasNextPage") }).to eq([true, false, false])
      expect(pages.first.fetch("nodes").first).to include(
        "raw" => first_post.raw,
        "cooked" => first_post.cooked,
        "author" => {
          "id" => first_post.user_id.to_s,
          "username" => first_post.user.username,
        },
      )
    end

    it "rejects invalid cursors, page sizes and cursors for another topic" do
      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               topicId: topic.id,
               first: 2,
             },
           },
           headers: headers,
           as: :json
      cursor = response.parsed_body.dig("data", "topicPosts", "pageInfo", "endCursor")
      expect(cursor).to be_present

      other_topic = Fabricate(:topic)
      [
        { topicId: topic.id, first: 51 },
        { topicId: topic.id, first: 0 },
        { topicId: topic.id, first: 2, after: "invalid" },
        { topicId: other_topic.id, first: 2, after: cursor },
        { topicId: topic.id, first: 3, after: cursor },
      ].each do |variables|
        post "/discourse-graphql/graphql",
             params: {
               query: query,
               variables: variables,
             },
             headers: headers,
             as: :json

        expect(response.status).to eq(200)
        expect(
          response.parsed_body.fetch("errors").map { |error| error.dig("extensions", "code") },
        ).to include("BAD_USER_INPUT")
        expect(response.parsed_body.dig("data", "topicPosts")).to be_nil
      end
    end

    it "preserves native ignored author and hidden post filtering" do
      ignored_author = second_post.user
      Fabricate(:ignored_user, user: user, ignored_user: ignored_author)
      third_post.update!(hidden: true)
      whisper = Fabricate(:post, topic: topic, post_type: Post.types[:whisper])

      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               topicId: topic.id,
               first: 20,
             },
           },
           headers: headers,
           as: :json

      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      expect(
        response.parsed_body.dig("data", "topicPosts", "nodes").map { |entry| entry.fetch("id") },
      ).to eq([first_post.id.to_s])
      expect(response.body).not_to include(second_post.user.username, whisper.user.username)
    end

    it "rechecks access when continuing a personal message" do
      message = Fabricate(:private_message_topic, user: user)
      Fabricate(:post, topic: message)
      Fabricate(:post, topic: message)
      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               topicId: message.id,
               first: 1,
             },
           },
           headers: headers,
           as: :json
      expect(response.parsed_body["errors"]).to be_blank
      cursor = response.parsed_body.dig("data", "topicPosts", "pageInfo", "endCursor")
      expect(cursor).to be_present

      message.topic_allowed_users.find_by!(user_id: user.id).destroy!
      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               topicId: message.id,
               first: 1,
               after: cursor,
             },
           },
           headers: headers,
           as: :json

      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("data", "topicPosts")).to be_nil
      expect(
        response.parsed_body.fetch("errors").map { |error| error.dig("extensions", "code") },
      ).to include("FORBIDDEN")
    end

    it "retains the native placeholder for the author's hidden content" do
      third_post.update!(hidden: true, user: user)

      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               topicId: topic.id,
               first: 20,
             },
           },
           headers: headers,
           as: :json

      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      hidden =
        response
          .parsed_body
          .dig("data", "topicPosts", "nodes")
          .find { |entry| entry.fetch("id") == third_post.id.to_s }
      expect(hidden.fetch("cooked")).to eq(I18n.t("flagging.you_must_edit", path: "/my/messages"))
      expect(hidden.fetch("raw")).to eq(third_post.raw)
    end

    it "bounds query growth across posts with distinct authors" do
      discussion = Fabricate(:topic)
      Fabricate.times(50, :post, topic: discussion)
      query_counts =
        [1, 50].map do |first|
          queries =
            track_sql_queries do
              post "/discourse-graphql/graphql",
                   params: {
                     query: query,
                     variables: {
                       topicId: discussion.id,
                       first: first,
                     },
                   },
                   headers: headers,
                   as: :json
            end

          expect(response.status).to eq(200)
          expect(response.parsed_body["errors"]).to be_blank
          expect(response.parsed_body.dig("data", "topicPosts", "nodes").size).to eq(first)
          queries.size
        end

      expect(query_counts[1]).to be <= query_counts[0] + 2
    end
  end
end
