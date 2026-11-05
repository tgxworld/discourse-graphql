require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController, type: %i[multisite request] do
  describe "#execute" do
    it "rejects cursor reuse on another site with the same actor and credential" do
      user = Fabricate(:user, refresh_auto_groups: true)
      channel = Fabricate(:category_channel, threading_enabled: true)
      channel.add(user)
      thread = Fabricate(:chat_thread, channel: channel, original_message_user: user)
      reply = Fabricate(:chat_message, chat_channel: channel, thread: thread)
      thread.update!(last_message: reply, replies_count: 1)
      api_key = Fabricate(:api_key, user: user)
      request_headers = { "Api-Key" => api_key.key, "Api-Username" => user.username }
      SiteSetting.chat_enabled = true
      SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
      get "/discourse-graphql/graphql", params: { query: "{ currentUserChatThreads(first: 1) { nodes { id } pageInfo { endCursor } } }" }, headers: request_headers
      expect(response.parsed_body["errors"]).to be_blank
      cursor = response.parsed_body.dig("data", "currentUserChatThreads", "pageInfo", "endCursor")
      expect(cursor).to be_present
      test_multisite_connection("second") do
        actor = Fabricate(:user, id: user.id, username: user.username, refresh_auto_groups: true)
        Fabricate(:api_key, user: actor, key_hash: api_key.key_hash, truncated_key: api_key.truncated_key)
        SiteSetting.chat_enabled = true
        SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
        get "http://test2.localhost/discourse-graphql/graphql", params: { query: "{ currentUserChatThreads(first: 1) { nodes { id } } currentUser { id } }" }, headers: request_headers
        expect(response.status).to eq(200)
        expect(response.parsed_body["errors"]).to be_blank
        expect(response.parsed_body.dig("data", "currentUser", "id")).to eq(user.id.to_s)
        query = "{ currentUserChatThreads(first: 1, after: #{cursor.to_json}) { nodes { id } } currentUser { id } }"
        get "http://test2.localhost/discourse-graphql/graphql", params: { query: query }, headers: request_headers
        expect(response.status).to eq(200)
        expect(response.parsed_body.dig("data", "currentUser", "id")).to eq(user.id.to_s)
        expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
    end
  end
end
