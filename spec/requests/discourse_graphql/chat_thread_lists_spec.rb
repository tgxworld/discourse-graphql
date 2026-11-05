require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:other_user, :user)
  fab!(:channel) { Fabricate(:category_channel, threading_enabled: true) }
  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    channel.add(user)
  end

  describe "#execute" do
    it "preserves channel list nonmembers and muted entries with native unread priority" do
      unread = make_thread(age_minutes: 30)
      unread.add(user)
      muted = make_thread(age_minutes: 10)
      muted.add(user, notification_level: 0)
      nonmember = make_thread(age_minutes: 5)
      get "/chat/api/channels/#{channel.id}/threads.json", params: { limit: 10 }, headers: headers
      expect(response.status).to eq(200)
      native = response.parsed_body
      result = list
      expect(result["errors"]).to be_blank
      page = result.dig("data", "chatChannelThreads")
      expect(page.fetch("nodes").map { |entry| entry.fetch("id") }).to eq(
        native.fetch("threads").map { |entry| entry.fetch("id").to_s },
      )
      expect(page.fetch("nodes").map { |entry| entry.fetch("id") }).to eq(
        [unread.id, nonmember.id, muted.id].map(&:to_s),
      )
      expected_tracking =
        native
          .fetch("tracking")
          .map do |id, value|
            {
              "threadId" => id.to_s,
              "channelId" => value.fetch("channel_id").to_s,
              "mentionCount" => value.fetch("mention_count").to_s,
              "unreadCount" => value.fetch("unread_count").to_s,
              "watchedThreadsUnreadCount" => value.fetch("watched_threads_unread_count").to_s,
            }
          end
      expect(page.fetch("tracking")).to eq(expected_tracking)
      expect(nonmember.membership_for(user)).to be_nil
      expect(unread.membership_for(user).last_read_message_id).to be_nil
    end

    it "retains current user membership and followed open channel filtering" do
      visible = make_thread
      visible.add(user)
      muted = make_thread(age_minutes: 2)
      muted.add(user, notification_level: 0)
      make_thread(age_minutes: 3)
      closed_channel = Fabricate(:category_channel, threading_enabled: true, status: :closed)
      closed_channel.add(user)
      closed = make_thread(channel: closed_channel)
      closed.add(user)
      unfollowed_channel = Fabricate(:category_channel, threading_enabled: true)
      unfollowed_channel.add(user).update!(following: false)
      unfollowed = make_thread(channel: unfollowed_channel)
      unfollowed.add(user)
      get "/chat/api/me/threads.json", headers: headers
      expect(response.status).to eq(200)
      native = response.parsed_body.fetch("threads")
      result = list(kind: :current)
      expect(result["errors"]).to be_blank
      ids = result.dig("data", "currentUserChatThreads", "nodes").map { |entry| entry.fetch("id") }
      expect(ids).to eq(native.map { |entry| entry.fetch("id").to_s })
      expect(ids).to eq([visible.id.to_s])
    end

    it "traverses exact full pages through an empty terminal response" do
      threads = 3.times.map { |index| make_thread(age_minutes: index + 1) }
      threads.each { |entry| entry.add(user) }
      %i[channel current].each do |kind|
        cursor = nil
        collected = []
        4.times do |index|
          result = list(kind: kind, first: 1, after: cursor)
          expect(result["errors"]).to be_blank
          page = result.fetch("data").values.first
          collected.concat(page.fetch("nodes").map { |entry| entry.fetch("id") })
          expect(page.dig("pageInfo", "hasNextPage")).to eq(index < 3)
          cursor = page.dig("pageInfo", "endCursor")
          expect(cursor.present?).to eq(index < 3)
          if index == 3
            expect(page.fetch("nodes")).to eq([])
            expect(page.fetch("tracking")).to be_nil
          end
        end
        expect(collected).to eq(threads.map { |entry| entry.id.to_s })
      end
    end

    it "ends short pages and retains empty native tracking maps" do
      entry = make_thread
      result = list(first: 2)
      expect(result["errors"]).to be_blank
      expect(
        result.dig("data", "chatChannelThreads", "nodes").map { |node| node.fetch("id") },
      ).to eq([entry.id.to_s])
      expect(result.dig("data", "chatChannelThreads", "tracking")).to eq([])
      expect(result.dig("data", "chatChannelThreads", "pageInfo")).to eq(
        "endCursor" => nil,
        "hasNextPage" => false,
      )
    end

    it "rejects changed cursor kind, channel, actor, size and malformed inputs" do
      make_thread
      cursor = list(first: 1).dig("data", "chatChannelThreads", "pageInfo", "endCursor")
      expect(cursor).to be_present
      other_channel = Fabricate(:category_channel, threading_enabled: true)
      other_key = Fabricate(:api_key, user: other_user)
      changes = [
        { kind: :current },
        { first: 2 },
        { channel_id: other_channel.id },
        { request_headers: { "Api-Key" => other_key.key, "Api-Username" => other_user.username } },
      ]
      changes.each do |change|
        result = list(first: 1, after: cursor, **change)
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
      [0, 11].each do |first|
        expect(list(first: first).dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
      ["invalid", "x" * 4097].each do |value|
        expect(list(after: value).dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
    end

    it "rechecks private access during channel and current user pagination" do
      group = Fabricate(:group)
      group.add(user)
      private_channel = Fabricate(:private_category_channel, group: group, threading_enabled: true)
      private_channel.add(user)
      first = make_thread(channel: private_channel)
      second = make_thread(channel: private_channel, age_minutes: 2)
      [first, second].each { |entry| entry.add(user) }
      channel_cursor =
        list(channel_id: private_channel.id, first: 1).dig(
          "data",
          "chatChannelThreads",
          "pageInfo",
          "endCursor",
        )
      user_cursor =
        list(kind: :current, first: 1).dig(
          "data",
          "currentUserChatThreads",
          "pageInfo",
          "endCursor",
        )
      expect(channel_cursor).to be_present
      expect(user_cursor).to be_present
      GroupUser.where(group: group, user: user).delete_all
      result = list(channel_id: private_channel.id, first: 1, after: channel_cursor)
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FORBIDDEN")
      result = list(kind: :current, first: 1, after: user_cursor)
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "currentUserChatThreads", "nodes")).to eq([])
      expect(response.body).not_to include(
        first.original_message.message,
        second.original_message.message,
      )
    end

    it "retains native deletion and disabled threading filters" do
      original_deleted = make_thread
      original_deleted.add(user)
      original_deleted.original_message.trash!
      last_deleted = make_thread(age_minutes: 2)
      last_deleted.add(user)
      last_deleted.last_message.trash!
      expect(list.dig("data", "chatChannelThreads", "nodes")).to eq([])
      expect(list(kind: :current).dig("data", "currentUserChatThreads", "nodes")).to eq([])
      channel.update!(threading_enabled: false)
      expect(list.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
      expect(list(kind: :current).dig("data", "currentUserChatThreads", "nodes")).to eq([])
    end

    it "keeps node restrictions and avoids unselected node or tracking rendering" do
      entry = make_thread
      restricted =
        Class.new(Chat::ThreadSerializer) do
          def initialize(object, options = {})
            super(object, options.merge(only: [:title]))
          end
        end
      entry.update!(title: "Visible title")
      stub_const(Chat, :ThreadSerializer, restricted) do
        result =
          list(
            first: 1,
            selection:
              "nodes { id title originalMessage { raw } } pageInfo { endCursor hasNextPage }",
          )
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "chatChannelThreads", "nodes")).to eq(
          [{ "id" => nil, "title" => "Visible title", "originalMessage" => nil }],
        )
        expect(result.dig("data", "chatChannelThreads", "pageInfo", "hasNextPage")).to eq(true)
      end
      Chat::ThreadSerializer.any_instance.stubs(:preview).raises("Preview unavailable")
      Chat::ThreadListSerializer.any_instance.stubs(:tracking).raises("Tracking unavailable")
      result = list(first: 1, selection: "pageInfo { endCursor hasNextPage }")
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatChannelThreads", "pageInfo", "hasNextPage")).to eq(true)
      result = list(selection: "nodes { id }")
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatChannelThreads", "nodes")).to eq([{ "id" => entry.id.to_s }])
    end

    it "preserves a withheld native collection without revealing its pagination" do
      make_thread
      restricted =
        Class.new(Chat::ThreadListSerializer) do
          def initialize(object, options = {})
            super(object, options.merge(only: [:tracking]))
          end
        end
      stub_const(Chat, :ThreadListSerializer, restricted) do
        result = list(first: 1)
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "chatChannelThreads")).to eq(
          "nodes" => nil,
          "tracking" => [],
          "pageInfo" => nil,
        )
      end
    end

    it "uses rows retained by the native collection getter for pagination" do
      make_thread
      filtered =
        Class.new(Chat::ThreadListSerializer) do
          def threads
            []
          end
        end
      stub_const(Chat, :ThreadListSerializer, filtered) do
        result = list(first: 1)
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "chatChannelThreads", "nodes")).to eq([])
        expect(result.dig("data", "chatChannelThreads", "pageInfo")).to eq(
          "endCursor" => nil,
          "hasNextPage" => false,
        )
      end
    end

    it "keeps native hidden profile status outside the serialized response" do
      SiteSetting.enable_user_status = true
      actor = Fabricate(:user)
      mentioned = Fabricate(:user)
      actor.set_status!("Hidden author status", "computer")
      mentioned.set_status!("Hidden mention status", "bulb")
      actor.user_option.update!(hide_profile: true)
      mentioned.user_option.update!(hide_profile: true)
      entry = make_thread(author: actor)
      entry.add(user)
      Fabricate(:user_chat_mention, chat_message: entry.original_message, user: mentioned)
      UserStatusSerializer.any_instance.stubs(:as_json).raises("Hidden status renderer evaluated")
      result =
        list(
          kind: :current,
          selection:
            "nodes { id originalMessage { author { id username } mentionedUsers { nodes { id username } } } }",
        )
      expect(result["errors"]).to be_blank
      expect(
        result.dig("data", "currentUserChatThreads", "nodes").map { |node| node.fetch("id") },
      ).to eq([entry.id.to_s])
    end

    it "retains native login, read credentials and disabled sibling results" do
      make_thread
      SiteSetting.chat_allowed_groups =
        "#{Group::AUTO_GROUPS[:everyone]}|#{Group::AUTO_GROUPS[:anonymous_users]}"
      %i[channel current].each do |kind|
        expect(list(kind: kind, request_headers: {}).dig("errors", 0, "extensions", "code")).to eq(
          "UNAUTHENTICATED",
        )
      end
      api_key.update!(
        scope_mode: :read_only,
        api_key_scopes: [ApiKeyScope.new(resource: "global", action: "read")],
      )
      expect(list["errors"]).to be_blank
      SiteSetting.chat_enabled = false
      query =
        "{ chatChannelThreads(channelId: \"#{channel.id}\") { nodes { id } } currentUserChatThreads { nodes { id } } currentUser { id } }"
      get "/discourse-graphql/graphql", params: { query: query }, headers: headers
      expect(response.parsed_body.fetch("data")).to eq(
        "chatChannelThreads" => nil,
        "currentUserChatThreads" => nil,
        "currentUser" => {
          "id" => user.id.to_s,
        },
      )
      expect(
        response.parsed_body.fetch("errors").map { |error| error.dig("extensions", "code") },
      ).to eq(["FEATURE_DISABLED"] * 2)
    end

    it "rejects excessive combined list work before evaluating native renderers" do
      make_thread
      Chat::ThreadListSerializer.any_instance.stubs(:threads).raises("Thread rendering unavailable")
      selections =
        11
          .times
          .map do |index|
            "page#{index}: chatChannelThreads(channelId: \"#{channel.id}\", first: 10) { nodes { id } }"
          end
          .join(" ")
      get "/discourse-graphql/graphql", params: { query: "{ #{selections} }" }, headers: headers
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
    end

    it "bounds selected list SQL growth with distinct authors and mentions while status is disabled" do
      SiteSetting.enable_user_status = false
      expected =
        10.times.map do |index|
          actor = Fabricate(:user)
          entry = make_thread(author: actor, age_minutes: index + 1)
          entry.add(user)
          Fabricate(
            :user_chat_mention,
            chat_message: entry.original_message,
            user: Fabricate(:user),
          )
          entry
        end
      selection =
        "nodes { id originalMessage { author { id username } mentionedUsers { nodes { id username } } } preview { lastReplyUser { id username } participantUsers { id username } } }"
      %i[channel current].each do |kind|
        list(kind: kind, first: 1, selection: selection)
        counts =
          [1, 10].map do |first|
            queries = track_sql_queries { list(kind: kind, first: first, selection: selection) }
            result = response.parsed_body
            expect(result["errors"]).to be_blank
            nodes = result.fetch("data").values.first.fetch("nodes")
            expect(nodes.map { |entry| entry.fetch("id") }).to eq(
              expected.first(first).map { |entry| entry.id.to_s },
            )
            queries.size
          end
        puts JSON.generate(
               measurement: "thread_list_sql",
               kind: kind,
               first: [1, 10],
               queries: counts,
               status_enabled: false,
             )
        expect(counts.last).to be <= counts.first + 2
      end
    end
  end

  private

  def make_thread(channel: self.channel, age_minutes: 1, author: other_user)
    entry = Fabricate(:chat_thread, channel: channel, original_message_user: author)
    reply =
      Fabricate(
        :chat_message,
        chat_channel: channel,
        thread: entry,
        user: author,
        created_at: age_minutes.minutes.ago,
      )
    entry.update!(last_message: reply, replies_count: 1)
    entry
  end

  def list(
    kind: :channel,
    channel_id: channel.id,
    first: 10,
    after: nil,
    selection: nil,
    request_headers: headers
  )
    field = kind == :channel ? "chatChannelThreads" : "currentUserChatThreads"
    arguments = ["first: #{first}"]
    arguments << "channelId: \"#{channel_id}\"" if kind == :channel
    arguments << "after: #{after.to_json}" if after
    selection ||=
      "nodes { id title originalMessage { id raw } currentUserMembership { notificationLevel } } tracking { threadId channelId mentionCount unreadCount watchedThreadsUnreadCount } pageInfo { endCursor hasNextPage }"
    get "/discourse-graphql/graphql",
        params: {
          query: "{ #{field}(#{arguments.join(", ")}) { #{selection} } }",
        },
        headers: request_headers
    response.parsed_body
  end
end
