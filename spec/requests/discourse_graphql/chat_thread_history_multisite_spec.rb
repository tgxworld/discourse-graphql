require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController, type: %i[multisite request] do
  describe "#execute" do
    it "rejects a history cursor on another site with matching actor and thread context" do
      user = Fabricate(:user, refresh_auto_groups: true)
      channel = Fabricate(:category_channel, threading_enabled: true)
      channel.add(user)
      thread = Fabricate(:chat_thread, channel: channel)
      reply = Fabricate(:chat_message, chat_channel: channel, thread: thread)
      thread.update!(last_message: reply)
      api_key = Fabricate(:api_key, user: user)
      request_headers = { "Api-Key" => api_key.key, "Api-Username" => user.username }
      SiteSetting.chat_enabled = true
      SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
      query = <<~GRAPHQL
        query History($channelId: ID!, $threadId: ID!, $before: String) {
          chatThreadMessages(channelId: $channelId, threadId: $threadId, last: 1, before: $before) {
            nodes { id }
            pageInfo { startCursor }
          }
          currentUser { id }
        }
      GRAPHQL
      get "/discourse-graphql/graphql",
          params: {
            query: query,
            variables: { channelId: channel.id, threadId: thread.id }.to_json,
          },
          headers: request_headers
      expect(response.parsed_body["errors"]).to be_blank
      cursor = response.parsed_body.dig("data", "chatThreadMessages", "pageInfo", "startCursor")
      expect(cursor).to be_present

      test_multisite_connection("second") do
        actor = Fabricate(:user, id: user.id, username: user.username, refresh_auto_groups: true)
        Fabricate(
          :api_key,
          user: actor,
          key_hash: api_key.key_hash,
          truncated_key: api_key.truncated_key,
        )
        local_channel = Fabricate(:category_channel, id: channel.id, threading_enabled: true)
        local_channel.add(actor)
        local_thread = Fabricate(:chat_thread, id: thread.id, channel: local_channel)
        local_reply = Fabricate(:chat_message, chat_channel: local_channel, thread: local_thread)
        local_thread.update!(last_message: local_reply)
        SiteSetting.chat_enabled = true
        SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
        variables = { channelId: channel.id, threadId: thread.id }
        get "http://test2.localhost/discourse-graphql/graphql",
            params: {
              query: query,
              variables: variables.to_json,
            },
            headers: request_headers
        expect(response.status).to eq(200)
        expect(response.parsed_body["errors"]).to be_blank
        expect(response.parsed_body.dig("data", "currentUser", "id")).to eq(user.id.to_s)
        expect(response.parsed_body.dig("data", "chatThreadMessages", "nodes", 0, "id")).to eq(
          local_reply.id.to_s,
        )

        get "http://test2.localhost/discourse-graphql/graphql",
            params: {
              query: query,
              variables: variables.merge(before: cursor).to_json,
            },
            headers: request_headers
        expect(response.status).to eq(200)
        expect(response.parsed_body.dig("data", "currentUser", "id")).to eq(user.id.to_s)
        expect(response.parsed_body.dig("data", "chatThreadMessages")).to be_nil
        expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
    end
  end
end
