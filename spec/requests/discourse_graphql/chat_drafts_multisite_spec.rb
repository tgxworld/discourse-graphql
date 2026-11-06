require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController, type: %i[multisite request] do
  describe "#execute" do
    it "rejects a draft cursor on another site with the same actor and native window" do
      user = Fabricate(:user, refresh_auto_groups: true)
      channel = Fabricate(:category_channel)
      thread = Fabricate(:chat_thread, channel: channel)
      timestamp = Time.zone.now
      Chat::Draft.create!(user: user, chat_channel: channel, data: "Channel", updated_at: timestamp)
      Chat::Draft.create!(
        user: user,
        chat_channel: channel,
        thread_id: thread.id,
        data: "Thread",
        updated_at: timestamp + 1,
      )
      api_key = Fabricate(:api_key, user: user)
      request_headers = { "Api-Key" => api_key.key, "Api-Username" => user.username }
      SiteSetting.chat_enabled = true
      SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
      query = <<~GRAPHQL
        query Drafts($after: String) {
          currentUserChatDrafts(first: 1, after: $after) {
            nodes { channelId threadId serializedData }
            pageInfo { endCursor }
          }
          currentUser { id }
        }
      GRAPHQL
      get "/discourse-graphql/graphql", params: { query: query }, headers: request_headers
      expect(response.parsed_body["errors"]).to be_blank
      first_page = response.parsed_body.dig("data", "currentUserChatDrafts", "nodes")
      cursor = response.parsed_body.dig("data", "currentUserChatDrafts", "pageInfo", "endCursor")
      expect(cursor).to be_present

      test_multisite_connection("second") do
        actor = Fabricate(:user, id: user.id, username: user.username, refresh_auto_groups: true)
        Fabricate(
          :api_key,
          user: actor,
          key_hash: api_key.key_hash,
          truncated_key: api_key.truncated_key,
        )
        local_channel = Fabricate(:category_channel, id: channel.id)
        local_thread = Fabricate(:chat_thread, id: thread.id, channel: local_channel)
        Chat::Draft.create!(
          user: actor,
          chat_channel: local_channel,
          data: "Channel",
          updated_at: timestamp,
        )
        Chat::Draft.create!(
          user: actor,
          chat_channel: local_channel,
          thread_id: local_thread.id,
          data: "Thread",
          updated_at: timestamp + 1,
        )
        SiteSetting.chat_enabled = true
        SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
        get "http://test2.localhost/discourse-graphql/graphql",
            params: {
              query: query,
            },
            headers: request_headers
        expect(response.status).to eq(200)
        expect(response.parsed_body["errors"]).to be_blank
        expect(response.parsed_body.dig("data", "currentUser", "id")).to eq(user.id.to_s)
        expect(response.parsed_body.dig("data", "currentUserChatDrafts", "nodes")).to eq(first_page)

        get "http://test2.localhost/discourse-graphql/graphql",
            params: {
              query: query,
              variables: { after: cursor }.to_json,
            },
            headers: request_headers
        expect(response.status).to eq(200)
        expect(response.parsed_body.dig("data", "currentUser", "id")).to eq(user.id.to_s)
        expect(response.parsed_body.dig("data", "currentUserChatDrafts")).to be_nil
        expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
    end
  end
end
