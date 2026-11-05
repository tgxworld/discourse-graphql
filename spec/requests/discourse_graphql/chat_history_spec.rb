require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user)
  fab!(:channel, :category_channel)
  fab!(:private_group, :group)
  fab!(:private_channel) { Fabricate(:private_category_channel, group: private_group) }

  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }
  let(:query) { <<~GRAPHQL }
      query History($channelId: ID!, $last: Int, $before: String) {
        chatMessages(channelId: $channelId, last: $last, before: $before) {
          nodes {
            id raw cooked excerpt createdAt deletedAt deletedById
            author { id username name avatarTemplate }
            threadId channelId streaming
          }
          pageInfo { startCursor hasPreviousPage endCursor hasNextPage }
        }
        currentUser { id }
      }
    GRAPHQL

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    channel.add(user)
  end

  describe "#execute" do
    it "reads native message content and traverses older pages in chronological order" do
      messages = Fabricate.times(3, :chat_message, chat_channel: channel)
      get "/chat/api/channels/#{channel.id}/messages", params: { page_size: 2 }, headers: headers
      expect(response.status).to eq(200)
      native = response.parsed_body.fetch("messages")

      cursor = nil
      pages =
        3.times.map do
          post "/discourse-graphql/graphql",
               params: {
                 query: query,
                 variables: {
                   channelId: channel.id,
                   last: 2,
                   before: cursor,
                 },
               },
               headers: headers,
               as: :json
          expect(response.status).to eq(200)
          expect(response.parsed_body["errors"]).to be_blank
          page = response.parsed_body.fetch("data").fetch("chatMessages")
          cursor = page.dig("pageInfo", "startCursor")
          page
        end

      expect(pages.map { |page| page.fetch("nodes").map { |message| message.fetch("id") } }).to eq(
        [messages.last(2).map { |message| message.id.to_s }, [messages.first.id.to_s], []],
      )
      expect(pages.map { |page| page.dig("pageInfo", "hasPreviousPage") }).to eq(
        [true, false, false],
      )
      expect(pages.map { |page| page.dig("pageInfo", "hasNextPage") }).to eq([false, false, false])
      expect(pages.last.dig("pageInfo", "startCursor")).to be_nil
      expect(pages.first.fetch("nodes").map { |message| message.fetch("raw") }).to eq(
        native.map { |message| message.fetch("message") },
      )
      expect(pages.first.fetch("nodes").map { |message| message.fetch("cooked") }).to eq(
        native.map { |message| message.fetch("cooked") },
      )
      expect(
        pages.first.fetch("nodes").map { |message| message.fetch("author").fetch("username") },
      ).to eq(native.map { |message| message.fetch("user").fetch("username") })
    end

    it "rejects invalid cursors, bounds and changed channel or page size" do
      Fabricate.times(2, :chat_message, chat_channel: channel)
      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               channelId: channel.id,
               last: 1,
             },
           },
           headers: headers,
           as: :json
      cursor = response.parsed_body.dig("data", "chatMessages", "pageInfo", "startCursor")
      expect(cursor).to be_present

      [
        { channelId: channel.id, last: 0 },
        { channelId: channel.id, last: 51 },
        { channelId: channel.id, before: "invalid" },
        { channelId: channel.id, last: 2, before: cursor },
        { channelId: private_channel.id, last: 1, before: cursor },
      ].each do |variables|
        post "/discourse-graphql/graphql",
             params: {
               query: query,
               variables: variables,
             },
             headers: headers,
             as: :json

        expect(response.parsed_body.dig("data", "chatMessages")).to be_nil
        expect(response.parsed_body.dig("data", "currentUser", "id")).to eq(user.id.to_s)
        expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
    end

    it "rechecks private channel access on every page and binds cursors to their actor" do
      messages = Fabricate.times(2, :chat_message, chat_channel: private_channel)
      private_group.add(user)
      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               channelId: private_channel.id,
               last: 1,
             },
           },
           headers: headers,
           as: :json
      cursor = response.parsed_body.dig("data", "chatMessages", "pageInfo", "startCursor")
      expect(cursor).to be_present

      other_user = Fabricate(:user)
      other_key = Fabricate(:api_key, user: other_user)
      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               channelId: private_channel.id,
               last: 1,
               before: cursor,
             },
           },
           headers: {
             "Api-Key" => other_key.key,
             "Api-Username" => other_user.username,
           },
           as: :json
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")

      private_group.remove(user)
      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               channelId: private_channel.id,
               last: 1,
               before: cursor,
             },
           },
           headers: headers,
           as: :json

      expect(response.parsed_body.dig("data", "chatMessages")).to be_nil
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("FORBIDDEN")
      expect(response.body).not_to include(*messages.map(&:message))
    end

    it "supports native public anonymous preview with null defaults and protects private messages" do
      message = Fabricate(:chat_message, chat_channel: channel)
      SiteSetting.chat_allowed_groups =
        "#{Group::AUTO_GROUPS[:everyone]}|#{Group::AUTO_GROUPS[:anonymous_users]}"

      get "/discourse-graphql/graphql",
          params: {
            query: query,
            variables: { channelId: channel.id, last: nil, before: nil }.to_json,
          }
      expect(response.parsed_body["errors"]).to be_blank
      expect(
        response.parsed_body.dig("data", "chatMessages", "nodes").map { |entry| entry.fetch("id") },
      ).to eq([message.id.to_s])

      get "/discourse-graphql/graphql",
          params: {
            query: query,
            variables: { channelId: private_channel.id }.to_json,
          }
      expect(response.parsed_body.dig("data", "chatMessages")).to be_nil
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("FORBIDDEN")
    end

    it "preserves native deleted visibility and thread filtering" do
      channel.update!(threading_enabled: true)
      original = Fabricate(:chat_message, chat_channel: channel)
      thread = Fabricate(:chat_thread, channel: channel, original_message: original)
      reply = Fabricate(:chat_message, chat_channel: channel, thread: thread)
      deleted = Fabricate(:chat_message, chat_channel: channel)
      deleted.trash!(Discourse.system_user)

      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               channelId: channel.id,
             },
           },
           headers: headers,
           as: :json
      expect(response.parsed_body["errors"]).to be_blank
      expect(
        response.parsed_body.dig("data", "chatMessages", "nodes").map { |entry| entry.fetch("id") },
      ).to eq([original.id.to_s])
      expect(response.body).not_to include(deleted.message, reply.message)

      admin = Fabricate(:admin)
      admin_key = Fabricate(:api_key, user: admin)
      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               channelId: channel.id,
             },
           },
           headers: {
             "Api-Key" => admin_key.key,
             "Api-Username" => admin.username,
           },
           as: :json
      expect(response.parsed_body["errors"]).to be_blank
      expect(
        response.parsed_body.dig("data", "chatMessages", "nodes").map { |entry| entry.fetch("id") },
      ).to eq([original.id.to_s, deleted.id.to_s])
    end

    it "represents the native missing author without fabricating identity" do
      message = Fabricate(:chat_message, chat_channel: channel)
      message.update_columns(user_id: nil)

      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               channelId: channel.id,
             },
           },
           headers: headers,
           as: :json

      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.dig("data", "chatMessages", "nodes", 0, "author")).to include(
        "id" => nil,
        "username" => I18n.t("chat.deleted_chat_username"),
        "avatarTemplate" => "/plugins/chat/images/deleted-chat-user-avatar.png",
      )
    end

    it "preserves native viewed state updates" do
      Fabricate(:chat_message, chat_channel: channel)
      freeze_time(Time.zone.now.change(usec: 0))
      channel.membership_for(user).update!(last_viewed_at: 1.day.ago)

      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               channelId: channel.id,
             },
           },
           headers: headers,
           as: :json

      expect(response.parsed_body["errors"]).to be_blank
      expect(channel.membership_for(user).reload.last_viewed_at.to_r).to eq(Time.zone.now.to_r)
      expect(user.reload.custom_fields[Chat::LAST_CHAT_CHANNEL_ID]).to eq(channel.id)
    end

    it "rejects a native reset after the cursor anchor becomes hidden" do
      messages = Fabricate.times(3, :chat_message, chat_channel: channel)
      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               channelId: channel.id,
               last: 2,
             },
           },
           headers: headers,
           as: :json
      cursor = response.parsed_body.dig("data", "chatMessages", "pageInfo", "startCursor")
      messages.second.trash!(Discourse.system_user)

      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               channelId: channel.id,
               last: 2,
               before: cursor,
             },
           },
           headers: headers,
           as: :json

      expect(response.parsed_body.dig("data", "chatMessages")).to be_nil
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
    end

    it "contains the native anonymous deleted anchor failure without exposing diagnostics" do
      messages = Fabricate.times(2, :chat_message, chat_channel: channel)
      SiteSetting.chat_allowed_groups =
        "#{Group::AUTO_GROUPS[:everyone]}|#{Group::AUTO_GROUPS[:anonymous_users]}"
      get "/discourse-graphql/graphql",
          params: {
            query: query,
            variables: { channelId: channel.id, last: 1 }.to_json,
          }
      cursor = response.parsed_body.dig("data", "chatMessages", "pageInfo", "startCursor")
      expect(cursor).to be_present
      messages.last.trash!(Discourse.system_user)

      get "/discourse-graphql/graphql",
          params: {
            query: query,
            variables: { channelId: channel.id, last: 1, before: cursor }.to_json,
          }

      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("data", "chatMessages")).to be_nil
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("INTERNAL_ERROR")
      expect(response.parsed_body.dig("errors", 0, "message")).to eq(
        I18n.t("discourse_graphql.errors.internal_error"),
      )
      expect(response.body).not_to include(
        "NoMethodError",
        "MessageExistence",
        "/var/www",
        *messages.map(&:message),
      )
    end

    it "uses the exact native timestamp and ID ordering for cursor progress" do
      timestamp = Time.zone.now.change(usec: 100_000)
      older_id = Fabricate(:chat_message, chat_channel: channel, created_at: timestamp + 0.5)
      newer_id = Fabricate(:chat_message, chat_channel: channel, created_at: timestamp)
      matching_time = Fabricate(:chat_message, chat_channel: channel, created_at: timestamp + 0.5)
      cursor = nil
      ids =
        3.times.map do
          post "/discourse-graphql/graphql",
               params: {
                 query: query,
                 variables: {
                   channelId: channel.id,
                   last: 1,
                   before: cursor,
                 },
               },
               headers: headers,
               as: :json
          expect(response.parsed_body["errors"]).to be_blank
          cursor = response.parsed_body.dig("data", "chatMessages", "pageInfo", "startCursor")
          response.parsed_body.dig("data", "chatMessages", "nodes", 0, "id")
        end

      expect(ids).to eq([matching_time.id.to_s, older_id.id.to_s, newer_id.id.to_s])
    end

    it "retains native missing target errors after hard removal" do
      message = Fabricate(:chat_message, chat_channel: channel)
      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               channelId: channel.id,
               last: 1,
             },
           },
           headers: headers,
           as: :json
      cursor = response.parsed_body.dig("data", "chatMessages", "pageInfo", "startCursor")
      expect(cursor).to be_present
      message.destroy!

      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               channelId: channel.id,
               last: 1,
               before: cursor,
             },
           },
           headers: headers,
           as: :json

      expect(response.parsed_body.dig("data", "chatMessages")).to be_nil
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
    end

    it "returns an empty terminal page when older messages are removed" do
      messages = Fabricate.times(2, :chat_message, chat_channel: channel)
      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               channelId: channel.id,
               last: 1,
             },
           },
           headers: headers,
           as: :json
      cursor = response.parsed_body.dig("data", "chatMessages", "pageInfo", "startCursor")
      expect(cursor).to be_present
      messages.first.destroy!

      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               channelId: channel.id,
               last: 1,
               before: cursor,
             },
           },
           headers: headers,
           as: :json

      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.dig("data", "chatMessages")).to eq(
        "nodes" => [],
        "pageInfo" => {
          "startCursor" => nil,
          "hasPreviousPage" => false,
          "endCursor" => nil,
          "hasNextPage" => false,
        },
      )
    end

    it "returns feature errors for disabled Chat while retaining permitted siblings" do
      SiteSetting.chat_enabled = false
      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               channelId: channel.id,
             },
           },
           headers: headers,
           as: :json

      expect(response.parsed_body.dig("data", "chatMessages")).to be_nil
      expect(response.parsed_body.dig("data", "currentUser", "id")).to eq(user.id.to_s)
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("FEATURE_DISABLED")
    end

    it "bounds SQL growth across messages with 50 distinct authors" do
      Fabricate.times(50, :chat_message, chat_channel: channel)
      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               channelId: channel.id,
             },
           },
           headers: headers,
           as: :json
      expect(response.parsed_body["errors"]).to be_blank

      counts =
        [1, 50].map do |limit|
          queries =
            track_sql_queries do
              post "/discourse-graphql/graphql",
                   params: {
                     query: query,
                     variables: {
                       channelId: channel.id,
                       last: limit,
                     },
                   },
                   headers: headers,
                   as: :json
            end
          expect(response.parsed_body["errors"]).to be_blank
          expect(response.parsed_body.dig("data", "chatMessages", "nodes").size).to eq(limit)
          queries.size
        end

      expect(counts[1]).to be <= counts[0] + 2
    end
  end
end
