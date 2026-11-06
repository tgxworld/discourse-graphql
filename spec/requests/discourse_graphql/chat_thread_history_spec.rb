require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:channel) { Fabricate(:category_channel, threading_enabled: true) }
  fab!(:thread) { Fabricate(:chat_thread, channel: channel) }
  fab!(:reply) { Fabricate(:chat_message, chat_channel: channel, thread: thread, user: user) }

  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    channel.add(user)
    thread.update!(last_message: reply)
  end

  describe "#execute" do
    it "starts at the latest native messages independently of membership reading state" do
      replies = Fabricate.times(3, :chat_message, chat_channel: channel, thread: thread)
      thread.update!(last_message: replies.last)
      membership = thread.add(user)
      membership.update!(last_read_message_id: thread.original_message_id)
      get "/chat/api/channels/#{channel.id}/threads/#{thread.id}/messages.json",
          params: {
            page_size: 2,
            direction: "past",
            fetch_from_last_message: true,
          },
          headers: headers
      expect(response.status).to eq(200)
      native = response.parsed_body.fetch("messages")

      result = history(last: 2)

      expect(result["errors"]).to be_blank
      nodes = result.dig("data", "chatThreadMessages", "nodes")
      expect(nodes.map { |node| node.fetch("id") }).to eq(native.map { |row| row.fetch("id").to_s })
      expect(nodes.map { |node| node.fetch("raw") }).to eq(
        native.map { |row| row.fetch("message") },
      )
      expect(nodes.map { |node| node.fetch("cooked") }).to eq(
        native.map { |row| row.fetch("cooked") },
      )
      expect(nodes.map { |node| node.dig("author", "username") }).to eq(
        native.map { |row| row.dig("user", "username") },
      )
      expect(membership.reload.last_read_message_id).to eq(thread.original_message_id)
    end

    it "traverses chronological pages through the original message and an empty terminal request" do
      replies = Fabricate.times(2, :chat_message, chat_channel: channel, thread: thread)
      thread.update!(last_message: replies.last)
      unrelated = Fabricate(:chat_message, chat_channel: channel)
      cursor = nil
      pages =
        3.times.map do
          result = history(last: 2, before: cursor)
          expect(result["errors"]).to be_blank
          page = result.dig("data", "chatThreadMessages")
          cursor = page.dig("pageInfo", "startCursor")
          page
        end

      expect(pages.map { |page| page.fetch("nodes").map { |node| node.fetch("id") } }).to eq(
        [
          replies.map { |message| message.id.to_s },
          [thread.original_message_id.to_s, reply.id.to_s],
          [],
        ],
      )
      expect(pages.map { |page| page.dig("pageInfo", "hasPreviousPage") }).to eq(
        [true, false, false],
      )
      expect(pages.map { |page| page.dig("pageInfo", "hasNextPage") }).to eq([false, false, false])
      expect(pages.last.dig("pageInfo", "startCursor")).to be_nil
      expect(pages.to_s).not_to include(unrelated.message)
      expect(thread.membership_for(user)).to be_nil
    end

    it "rejects malformed cursors and changed pagination context while preserving siblings" do
      cursor = history(last: 1).dig("data", "chatThreadMessages", "pageInfo", "startCursor")
      expect(cursor).to be_present
      other_thread = Fabricate(:chat_thread, channel: channel)
      other_channel = Fabricate(:category_channel, threading_enabled: true)
      [
        { last: 0 },
        { last: 51 },
        { before: "invalid" },
        { before: "x" * 4097 },
        { last: 2, before: cursor },
        { last: 1, before: cursor, thread_id: other_thread.id },
        { last: 1, before: cursor, channel_id: other_channel.id },
      ].each do |arguments|
        result = history(**arguments)
        expect(result.dig("data", "chatThreadMessages")).to be_nil
        expect(result.dig("data", "currentUser", "id")).to eq(user.id.to_s)
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end

      other_user = Fabricate(:user)
      other_key = Fabricate(:api_key, user: other_user)
      result =
        history(
          last: 1,
          before: cursor,
          request_headers: {
            "Api-Key" => other_key.key,
            "Api-Username" => other_user.username,
          },
        )
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
    end

    it "keeps channel history cursors outside the thread history purpose" do
      get "/discourse-graphql/graphql",
          params: {
            query:
              "{ chatMessages(channelId: \"#{channel.id}\", last: 1) { pageInfo { startCursor } } }",
          },
          headers: headers
      cursor = response.parsed_body.dig("data", "chatMessages", "pageInfo", "startCursor")
      expect(cursor).to be_present

      result = history(last: 1, before: cursor)

      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
    end

    it "requires the thread to belong to the requested channel" do
      other_channel = Fabricate(:category_channel, threading_enabled: true)
      other_channel.add(user)

      result = history(channel_id: other_channel.id)

      expect(result.dig("data", "chatThreadMessages")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
      expect(result.to_s).not_to include(reply.message)
    end

    it "rechecks private channel access on continuation" do
      group = Fabricate(:group)
      group.add(user)
      private_channel = Fabricate(:private_category_channel, group: group, threading_enabled: true)
      private_thread = Fabricate(:chat_thread, channel: private_channel)
      private_reply =
        Fabricate(:chat_message, chat_channel: private_channel, thread: private_thread)
      private_thread.update!(last_message: private_reply)
      cursor =
        history(channel_id: private_channel.id, thread_id: private_thread.id, last: 1).dig(
          "data",
          "chatThreadMessages",
          "pageInfo",
          "startCursor",
        )
      expect(cursor).to be_present
      group.remove(user)

      result =
        history(
          channel_id: private_channel.id,
          thread_id: private_thread.id,
          last: 1,
          before: cursor,
        )

      expect(result.dig("data", "chatThreadMessages")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FORBIDDEN")
      expect(result.to_s).not_to include(private_reply.message)
    end

    it "retains native readonly category denial" do
      group = Fabricate(:group, users: [user])
      category =
        Fabricate(
          :private_category,
          group: group,
          permission_type: CategoryGroup.permission_types[:readonly],
        )
      readonly_channel = Fabricate(:category_channel, chatable: category, threading_enabled: true)
      readonly_thread = Fabricate(:chat_thread, channel: readonly_channel)

      result = history(channel_id: readonly_channel.id, thread_id: readonly_thread.id)

      expect(result.dig("data", "chatThreadMessages")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FORBIDDEN")
    end

    it "retains native forced thread access when channel threading is disabled" do
      channel.update!(threading_enabled: false)
      result = history
      expect(result.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
      thread.update!(force: true)

      result = history

      expect(result["errors"]).to be_blank
      expect(
        result.dig("data", "chatThreadMessages", "nodes").map { |node| node.fetch("id") },
      ).to eq([thread.original_message_id.to_s, reply.id.to_s])
    end

    it "preserves native moderation of a deleted thread original" do
      thread.original_message.trash!(Discourse.system_user)
      result = history
      expect(result.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
      user.update!(admin: true)
      get "/chat/api/channels/#{channel.id}/threads/#{thread.id}/messages.json",
          params: {
            direction: "past",
            fetch_from_last_message: true,
          },
          headers: headers
      expect(response.status).to eq(200)
      native_ids = response.parsed_body.fetch("messages").map { |message| message.fetch("id").to_s }

      result = history

      expect(result["errors"]).to be_blank
      expect(
        result.dig("data", "chatThreadMessages", "nodes").map { |node| node.fetch("id") },
      ).to eq(native_ids)
    end

    it "supports native anonymous preview and read credentials through GET" do
      SiteSetting.chat_allowed_groups =
        "#{Group::AUTO_GROUPS[:everyone]}|#{Group::AUTO_GROUPS[:anonymous_users]}"
      result = history(request_headers: {})
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "currentUser")).to be_nil
      expect(
        result.dig("data", "chatThreadMessages", "nodes").map { |node| node.fetch("id") },
      ).to eq([thread.original_message_id.to_s, reply.id.to_s])
      api_key.update!(
        scope_mode: :read_only,
        api_key_scopes: [ApiKeyScope.new(resource: "global", action: "read")],
      )

      result = history

      expect(result["errors"]).to be_blank
      expect(result.dig("data", "currentUser", "id")).to eq(user.id.to_s)
    end

    it "retains native target failure after a cursor anchor is removed" do
      cursor = history(last: 1).dig("data", "chatThreadMessages", "pageInfo", "startCursor")
      expect(cursor).to be_present
      reply.destroy!

      result = history(last: 1, before: cursor)

      expect(result.dig("data", "chatThreadMessages")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
    end

    it "preserves a native withheld message collection without exposing cursor identity" do
      restricted =
        Class.new(Chat::MessagesSerializer) do
          def include_messages?
            false
          end
        end
      stub_const(Chat, :MessagesSerializer, restricted) do
        result = history(last: 1)
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "chatThreadMessages")).to eq("nodes" => nil, "pageInfo" => nil)
      end
    end

    it "uses the permitted native collection when message filtering removes the page" do
      filtered =
        Class.new(Chat::MessagesSerializer) do
          def messages
            []
          end
        end
      stub_const(Chat, :MessagesSerializer, filtered) do
        result = history(last: 1)
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "chatThreadMessages")).to eq("nodes" => [], "pageInfo" => nil)
      end
    end

    it "contains the native anonymous deleted anchor failure without leaking diagnostics" do
      SiteSetting.chat_allowed_groups =
        "#{Group::AUTO_GROUPS[:everyone]}|#{Group::AUTO_GROUPS[:anonymous_users]}"
      cursor =
        history(last: 1, request_headers: {}).dig(
          "data",
          "chatThreadMessages",
          "pageInfo",
          "startCursor",
        )
      expect(cursor).to be_present
      reply.trash!(Discourse.system_user)

      result = history(last: 1, before: cursor, request_headers: {})

      expect(result.dig("data", "chatThreadMessages")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("INTERNAL_ERROR")
      expect(result.dig("errors", 0, "message")).to eq(
        I18n.t("discourse_graphql.errors.internal_error"),
      )
      expect(result.to_s).not_to include("NoMethodError", "MessageExistence", reply.message)
    end

    it "retains overrides on native message serializer instances" do
      decorated =
        Class.new(Chat::MessagesSerializer) do
          def messages
            super.each do |serializer|
              serializer.define_singleton_method(:message) { "Native retained #{object.id}" }
            end
          end
        end
      stub_const(Chat, :MessagesSerializer, decorated) do
        get "/chat/api/channels/#{channel.id}/threads/#{thread.id}/messages.json",
            params: {
              direction: "past",
              fetch_from_last_message: true,
            },
            headers: headers
        expect(response.status).to eq(200)
        native = response.parsed_body.fetch("messages").map { |row| row.fetch("message") }

        result = history

        expect(result["errors"]).to be_blank
        expect(
          result.dig("data", "chatThreadMessages", "nodes").map { |row| row.fetch("raw") },
        ).to eq(native)
      end
    end

    it "skips unselected native message renderers" do
      restricted =
        Class.new(Chat::MessageSerializer) do
          def cooked
            raise "Selected cooked renderer unavailable"
          end
        end
      stub_const(Chat, :MessageSerializer, restricted) do
        result = history(selection: "nodes { id } pageInfo { startCursor }")
        expect(result["errors"]).to be_blank
        expect(
          result.dig("data", "chatThreadMessages", "nodes").map { |node| node.fetch("id") },
        ).to eq([thread.original_message_id.to_s, reply.id.to_s])
        result = history
        expect(result.dig("data", "chatThreadMessages")).to be_nil
        expect(result.dig("errors", 0, "extensions", "code")).to eq("INTERNAL_ERROR")
      end
    end

    it "withholds continuation when native row identity is excluded" do
      restricted =
        Class.new(Chat::MessageSerializer) do
          def include_id?
            false
          end
        end
      stub_const(Chat, :MessageSerializer, restricted) do
        result =
          history(last: 1, selection: "nodes { raw } pageInfo { startCursor hasPreviousPage }")
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "chatThreadMessages")).to eq(
          "nodes" => [{ "raw" => reply.message }],
          "pageInfo" => nil,
        )
      end
    end

    it "uses exact native timestamp and ID ordering across tied fractional timestamps" do
      timestamp = 1.minute.from_now.change(usec: 100_000)
      first =
        Fabricate(:chat_message, chat_channel: channel, thread: thread, created_at: timestamp + 0.5)
      second =
        Fabricate(:chat_message, chat_channel: channel, thread: thread, created_at: timestamp)
      third =
        Fabricate(:chat_message, chat_channel: channel, thread: thread, created_at: timestamp + 0.5)
      thread.update!(last_message: third)
      cursor = nil
      ids =
        3.times.map do
          result = history(last: 1, before: cursor)
          expect(result["errors"]).to be_blank
          cursor = result.dig("data", "chatThreadMessages", "pageInfo", "startCursor")
          result.dig("data", "chatThreadMessages", "nodes", 0, "id")
        end
      expect(ids).to eq([third.id.to_s, first.id.to_s, second.id.to_s])
    end

    it "bounds complete SQL growth for 50 messages with distinct authors and reactions" do
      SiteSetting.enable_user_status = true
      messages =
        Array.new(50) do
          author = Fabricate(:user)
          message = Fabricate(:chat_message, chat_channel: channel, thread: thread, user: author)
          Fabricate(:chat_message_reaction, chat_message: message, user: author, emoji: "heart")
          message
        end
      thread.update!(last_message: messages.last)
      selection =
        "nodes { id raw author { id username } reactions(first: 1) { nodes { emoji count reacted users { id username } } } } pageInfo { startCursor hasPreviousPage }"
      [1, 50].each do |size|
        result = history(last: size, selection: selection)
        expect(result["errors"]).to be_blank
      end
      counts =
        [1, 50].map do |size|
          queries =
            track_sql_queries do
              result = history(last: size, selection: selection)
              expect(result["errors"]).to be_blank
              expect(result.dig("data", "chatThreadMessages", "nodes").size).to eq(size)
            end
          queries.count { |sql| sql.match?(/\A\s*(SELECT|WITH)\b/i) }
        end
      puts({ measurement: "chat_thread_message_sql", page_sizes: [1, 50], queries: counts }.to_json)
      expect(counts.last).to be <= counts.first + 3
    end

    it "keeps disabled Chat nullable and preserves enabled siblings" do
      SiteSetting.chat_enabled = false

      result = history

      expect(result.dig("data", "chatThreadMessages")).to be_nil
      expect(result.dig("data", "currentUser", "id")).to eq(user.id.to_s)
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FEATURE_DISABLED")
    end
  end

  def history(
    channel_id: channel.id,
    thread_id: thread.id,
    last: 25,
    before: nil,
    request_headers: headers,
    selection: nil
  )
    selection ||=
      "nodes { id raw cooked createdAt author { id username } threadId channelId } pageInfo { startCursor hasPreviousPage endCursor hasNextPage }"
    query = <<~GRAPHQL
      query ThreadHistory($channelId: ID!, $threadId: ID!, $last: Int, $before: String) {
        chatThreadMessages(channelId: $channelId, threadId: $threadId, last: $last, before: $before) {
          #{selection}
        }
        currentUser { id }
      }
    GRAPHQL
    get "/discourse-graphql/graphql",
        params: {
          query: query,
          variables: {
            channelId: channel_id,
            threadId: thread_id,
            last: last,
            before: before,
          }.to_json,
        },
        headers: request_headers
    expect(response.status).to eq(200)
    response.parsed_body
  end
end
