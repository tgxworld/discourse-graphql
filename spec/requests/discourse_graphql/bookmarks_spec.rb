require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:other_user, :user)
  fab!(:bookmark_post, :post)
  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }
  let(:list_query) do
    "query Bookmarks($first: Int, $after: String, $search: String) { bookmarks(first: $first, after: $after, search: $search) { nodes { id name reminderAt autoDeletePreference pinned title fancyTitle excerpt targetId targetType targetUrl createdAt updatedAt } pageInfo { endCursor hasNextPage } } }"
  end

  describe "#execute" do
    it "creates post and topic bookmarks with native topic state and reads native metadata" do
      reminder = 1.day.from_now.iso8601
      result =
        graphql(
          query:
            "mutation { createBookmark(input: { targetId: \"#{bookmark_post.id}\", targetType: POST, name: \"Read this later\", reminderAt: \"#{reminder}\", autoDeletePreference: CLEAR_REMINDER }) { success id errors { code } } topicBookmark: createBookmark(input: { targetId: \"#{bookmark_post.topic_id}\", targetType: TOPIC }) { success id } }",
        )
      expect(result["errors"]).to be_blank
      bookmark_id = result.dig("data", "createBookmark", "id")
      expect(result.dig("data", "createBookmark", "success")).to eq(true)
      expect(result.dig("data", "topicBookmark", "success")).to eq(true)
      bookmark = Bookmark.find(bookmark_id)
      expect(
        bookmark.attributes.slice(
          "user_id",
          "bookmarkable_id",
          "bookmarkable_type",
          "name",
          "auto_delete_preference",
        ),
      ).to eq(
        "user_id" => user.id,
        "bookmarkable_id" => bookmark_post.id,
        "bookmarkable_type" => "Post",
        "name" => "Read this later",
        "auto_delete_preference" => Bookmark.auto_delete_preferences[:clear_reminder],
      )
      expect(bookmark.reminder_at.to_r).to eq(Time.iso8601(reminder).to_r)
      expect(
        graphql(query: list_query)
          .dig("data", "bookmarks", "nodes")
          .find { |node| node["id"] == bookmark_id }[
          "autoDeletePreference"
        ],
      ).to eq("CLEAR_REMINDER")
      expect(TopicUser.find_by(user: user, topic: bookmark_post.topic).bookmarked).to eq(true)
      get "/u/#{user.username}/bookmarks.json", headers: headers
      native = response.parsed_body.dig("user_bookmark_list", "bookmarks")
      result = graphql(query: list_query)
      expect(result["errors"]).to be_blank
      nodes = result.dig("data", "bookmarks", "nodes")
      expect(nodes.map { |node| node.fetch("id") }).to eq(
        native.map { |node| node.fetch("id").to_s },
      )
      nodes
        .zip(native)
        .each do |node, expected|
          expect(node).to include(
            "name" => expected["name"],
            "pinned" => expected["pinned"],
            "title" => expected["title"],
            "fancyTitle" => expected["fancy_title"],
            "excerpt" => expected["excerpt"],
            "targetId" => expected["bookmarkable_id"].to_s,
            "targetType" => expected["bookmarkable_type"],
            "targetUrl" => expected["bookmarkable_url"],
          )
        end
    end

    it "retains native ordering, search, cursor binding and current access" do
      ids =
        3.times.map do |index|
          target = Fabricate(:post)
          bookmark =
            BookmarkManager.new(user).create_for(
              bookmarkable_id: target.id,
              bookmarkable_type: "Post",
              name: "Needle #{index}",
            )
          bookmark.update!(updated_at: (index + 1).minutes.ago)
          bookmark.id.to_s
        end
      result = graphql(query: list_query, variables: { first: 2, search: "Needle" })
      expect(result.dig("data", "bookmarks", "nodes").map { |node| node.fetch("id") }).to eq(
        ids.first(2),
      )
      cursor = result.dig("data", "bookmarks", "pageInfo", "endCursor")
      result = graphql(query: list_query, variables: { first: 2, search: "Needle", after: cursor })
      expect(result.dig("data", "bookmarks", "nodes").map { |node| node.fetch("id") }).to eq(
        ids.last(1),
      )
      expect(result.dig("data", "bookmarks", "pageInfo")).to eq(
        "endCursor" => nil,
        "hasNextPage" => false,
      )
      [
        { first: 1, search: "Needle", after: cursor },
        { first: 2, search: "Other", after: cursor },
        { after: "invalid" },
        { first: 0 },
        { first: 21 },
        { search: "x" * 201 },
      ].each do |variables|
        result = graphql(query: list_query, variables: variables)
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
      key = Fabricate(:api_key, user: other_user)
      result =
        graphql(
          query: list_query,
          variables: {
            first: 2,
            search: "Needle",
            after: cursor,
          },
          request_headers: {
            "Api-Key" => key.key,
            "Api-Username" => other_user.username,
          },
        )
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      hidden = Bookmark.find(ids.last)
      hidden.bookmarkable.topic.update!(
        category: Fabricate(:private_category, group: Fabricate(:group)),
      )
      result = graphql(query: list_query, variables: { first: 2, search: "Needle", after: cursor })
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "bookmarks", "nodes")).to eq([])
    end

    it "retains native reminder replacement, pin toggle and removal effects" do
      bookmark =
        BookmarkManager.new(user).create_for(
          bookmarkable_id: bookmark_post.id,
          bookmarkable_type: "Post",
          name: "Old note",
          reminder_at: 1.day.from_now.iso8601,
        )
      bookmark.update!(pinned: true, reminder_last_sent_at: 1.hour.ago)
      result =
        graphql(
          query:
            "mutation { updateBookmark(input: { id: \"#{bookmark.id}\", name: null, reminderAt: null, autoDeletePreference: NEVER }) { success errors { code } } }",
        )
      expect(result.dig("data", "updateBookmark", "success")).to eq(true)
      expect(bookmark.reload.name).to be_nil
      expect(bookmark.reminder_at).to be_nil
      expect(bookmark.reminder_last_sent_at).to be_nil
      expect(bookmark.pinned).to be_nil
      expect(bookmark.auto_delete_preference).to eq(Bookmark.auto_delete_preferences[:never])
      result = graphql(query: "mutation { toggleBookmarkPin(id: \"#{bookmark.id}\") { success } }")
      expect(result.dig("data", "toggleBookmarkPin", "success")).to eq(true)
      expect(bookmark.reload.pinned).to eq(true)
      result =
        graphql(
          query:
            "mutation { deleteBookmark(id: \"#{bookmark.id}\") { success topicBookmarked errors { code } } }",
        )
      expect(result.dig("data", "deleteBookmark")).to eq(
        "success" => true,
        "topicBookmarked" => false,
        "errors" => [],
      )
      expect(Bookmark.exists?(bookmark.id)).to eq(false)
      expect(TopicUser.find_by(user: user, topic: bookmark_post.topic).bookmarked).to eq(false)
    end

    it "requires explicit nullable replacement fields before updating a bookmark" do
      bookmark =
        BookmarkManager.new(user).create_for(
          bookmarkable_id: bookmark_post.id,
          bookmarkable_type: "Post",
          name: "Keep this",
        )
      graphql(query: "mutation { updateBookmark(input: { id: \"#{bookmark.id}\" }) { success } }")
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq(
        "GRAPHQL_VALIDATION_FAILED",
      )
      expect(bookmark.reload.name).to eq("Keep this")
    end

    it "keeps native creation permission, validation, duplicate and rate limits" do
      private_post = Fabricate(:post, topic: Fabricate(:private_message_topic))
      result =
        graphql(
          query:
            "mutation { createBookmark(input: { targetType: POST, targetId: \"#{private_post.id}\" }) { success errors { code } } }",
        )
      expect(result.dig("data", "createBookmark", "errors", 0, "code")).to eq("FORBIDDEN")
      result =
        graphql(
          query:
            "mutation { createBookmark(input: { targetType: POST, targetId: \"#{bookmark_post.id}\", name: \"#{"x" * 101}\" }) { success errors { code } } }",
        )
      expect(result.dig("data", "createBookmark", "errors", 0, "code")).to eq("BAD_USER_INPUT")
      result =
        graphql(
          query:
            "mutation { first: createBookmark(input: { targetType: POST, targetId: \"#{bookmark_post.id}\" }) { success } duplicate: createBookmark(input: { targetType: POST, targetId: \"#{bookmark_post.id}\" }) { success errors { code } } }",
        )
      expect(result.dig("data", "first", "success")).to eq(true)
      expect(result.dig("data", "duplicate", "errors", 0, "code")).to eq("BAD_USER_INPUT")
      SiteSetting.max_bookmarks_per_day = 1
      RateLimiter.enable
      RateLimiter.new(user, "create_bookmark", 1, 1.day.to_i).clear!
      post "/bookmarks.json",
           params: {
             bookmarkable_id: bookmark_post.id,
             bookmarkable_type: "Post",
           },
           headers: headers
      result =
        graphql(
          query:
            "mutation { createBookmark(input: { targetType: TOPIC, targetId: \"#{bookmark_post.topic_id}\" }) { success errors { code retryAfterSeconds } } }",
        )
      expect(result.dig("data", "createBookmark", "errors", 0, "code")).to eq("RATE_LIMITED")
      expect(result.dig("data", "createBookmark", "errors", 0, "retryAfterSeconds")).to be_positive
    end

    it "protects another actor's bookmark across every native write" do
      foreign =
        BookmarkManager.new(other_user).create_for(
          bookmarkable_id: bookmark_post.id,
          bookmarkable_type: "Post",
          name: "Private note",
        )
      operations = [
        "updateBookmark(input: { id: \"#{foreign.id}\", name: null, reminderAt: null, autoDeletePreference: null })",
        "deleteBookmark(id: \"#{foreign.id}\")",
        "toggleBookmarkPin(id: \"#{foreign.id}\")",
        "bulkBookmarks(ids: [\"#{foreign.id}\"], operation: DELETE)",
      ]
      operations.each do |operation|
        result = graphql(query: "mutation { #{operation} { success errors { code } } }")
        expect(result.fetch("data").values.first.dig("errors", 0, "code")).to eq("FORBIDDEN")
      end
      expect(foreign.reload.name).to eq("Private note")
      expect(graphql(query: list_query).dig("data", "bookmarks", "nodes")).to eq([])
    end

    it "performs bounded native bulk reminder clearing and deletion" do
      bookmarks =
        [bookmark_post, Fabricate(:post)].map do |target|
          BookmarkManager.new(user).create_for(
            bookmarkable_id: target.id,
            bookmarkable_type: "Post",
            reminder_at: 1.day.from_now.iso8601,
          )
        end
      ids = bookmarks.map(&:id)
      query =
        "mutation Bulk($ids: [ID!]!, $operation: BookmarkBulkOperation!) { bulkBookmarks(ids: $ids, operation: $operation) { success changedIds errors { code } } }"
      result =
        graphql(query: query, variables: { ids: ids.map(&:to_s), operation: "CLEAR_REMINDER" })
      expect(result.dig("data", "bulkBookmarks", "changedIds")).to eq(ids.sort.map(&:to_s))
      expect(bookmarks.map { |bookmark| bookmark.reload.reminder_at }).to eq([nil, nil])
      result = graphql(query: query, variables: { ids: 51.times.map(&:to_s), operation: "DELETE" })
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      expect(Bookmark.where(id: ids).count).to eq(2)
      result = graphql(query: query, variables: { ids: ids.map(&:to_s), operation: "DELETE" })
      expect(result.dig("data", "bulkBookmarks", "changedIds")).to eq(ids.sort.map(&:to_s))
      expect(Bookmark.where(id: ids)).to be_empty
    end

    it "retains anonymous, GET, readonly and prewrite cost protections" do
      result =
        graphql(query: "{ bookmarks { nodes { id } } currentUser { id } }", request_headers: {})
      expect(result.dig("errors", 0, "extensions", "code")).to eq("UNAUTHENTICATED")
      expect(result.dig("data", "bookmarks")).to be_nil
      expect(result.dig("data", "currentUser")).to be_nil
      query =
        "mutation { createBookmark(input: { targetType: POST, targetId: \"#{bookmark_post.id}\" }) { success errors { code } } }"
      result = graphql(query: query, request_headers: {})
      expect(result.dig("data", "createBookmark", "errors", 0, "code")).to eq("UNAUTHENTICATED")
      get "/discourse-graphql/graphql", params: { query: query }, headers: headers
      expect(response.status).to eq(400)
      selections =
        10.times.map do |index|
          "save#{index}: createBookmark(input: { targetType: POST, targetId: \"#{bookmark_post.id}\" }) { success }"
        end
      graphql(query: "mutation { #{selections.join(" ")} }")
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
      Discourse.enable_readonly_mode
      begin
        graphql(query: query)
        expect(response.status).to eq(503)
      ensure
        Discourse.disable_readonly_mode
      end
      expect(Bookmark.where(user: user)).to be_empty
    end

    it "uses the enabled native Chat bookmark registration and current channel access" do
      SiteSetting.chat_enabled = true
      SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
      channel = Fabricate(:category_channel)
      channel.add(user)
      message = Fabricate(:chat_message, chat_channel: channel)
      result =
        graphql(
          query:
            "mutation { createBookmark(input: { targetType: CHAT_MESSAGE, targetId: \"#{message.id}\" }) { success id errors { code } } }",
        )
      expect(result.dig("data", "createBookmark", "success")).to eq(true)
      id = result.dig("data", "createBookmark", "id")
      result = graphql(query: list_query)
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "bookmarks", "nodes").map { |node| node.fetch("id") }).to eq([id])
      group = Fabricate(:group)
      group.add(user)
      private_channel = Fabricate(:private_category_channel, group: group)
      private_channel.add(user)
      private_message = Fabricate(:chat_message, chat_channel: private_channel)
      result =
        graphql(
          query:
            "mutation { createBookmark(input: { targetType: CHAT_MESSAGE, targetId: \"#{private_message.id}\" }) { success } }",
        )
      expect(result.dig("data", "createBookmark", "success")).to eq(true)
      group.remove(user)
      result = graphql(query: list_query)
      expect(result.dig("data", "bookmarks", "nodes").map { |node| node.fetch("id") }).to eq([id])
      result =
        graphql(
          query:
            "mutation { createBookmark(input: { targetType: CHAT_MESSAGE, targetId: \"#{private_message.id}\" }) { success errors { code } } }",
        )
      expect(result.dig("data", "createBookmark", "errors", 0, "code")).to eq("FORBIDDEN")
      SiteSetting.chat_enabled = false
      expect(graphql(query: list_query).dig("data", "bookmarks", "nodes")).to eq([])
      result =
        graphql(
          query:
            "mutation { createBookmark(input: { targetType: CHAT_MESSAGE, targetId: \"#{message.id}\" }) { success errors { code } } }",
        )
      expect(result.dig("data", "createBookmark", "errors", 0, "code")).to eq("BAD_USER_INPUT")
    end

    it "contains the native disabled target deletion failure without claiming rollback" do
      SiteSetting.chat_enabled = true
      SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
      channel = Fabricate(:category_channel)
      channel.add(user)
      message = Fabricate(:chat_message, chat_channel: channel)
      bookmark =
        BookmarkManager.new(user).create_for(
          bookmarkable_id: message.id,
          bookmarkable_type: "Chat::Message",
        )
      SiteSetting.chat_enabled = false
      result = graphql(query: "mutation { deleteBookmark(id: \"#{bookmark.id}\") { success } }")
      expect(result.dig("data", "deleteBookmark")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("INTERNAL_ERROR")
      expect(result.to_json).not_to include("after_destroy", "BookmarkManager", "NoMethodError")
      expect(Bookmark.exists?(bookmark.id)).to eq(false)
    end

    it "retains native reminder delivery and reads the resulting notification" do
      freeze_time
      reminder = 1.minute.from_now.iso8601
      result =
        graphql(
          query:
            "mutation { createBookmark(input: { targetId: \"#{bookmark_post.id}\", targetType: POST, reminderAt: \"#{reminder}\", autoDeletePreference: CLEAR_REMINDER }) { success id } }",
        )
      id = result.dig("data", "createBookmark", "id")
      expect(result.dig("data", "createBookmark", "success")).to eq(true)
      freeze_time 2.minutes.from_now
      Jobs::BookmarkReminderNotifications.new.execute
      notification =
        Notification.find_by(user: user, notification_type: Notification.types[:bookmark_reminder])
      expect(notification).to be_present
      expect(notification.data_hash[:bookmark_id]).to eq(id.to_i)
      expect(Bookmark.find(id).reminder_at).to be_nil
      result = graphql(query: "{ notifications { nodes { id notificationType topicId } } }")
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "notifications", "nodes")).to include(
        "id" => notification.id.to_s,
        "notificationType" => Notification.types[:bookmark_reminder],
        "topicId" => bookmark_post.topic_id.to_s,
      )
    end

    it "preserves reminder precision through creation and replacement" do
      reminder = 1.day.from_now.change(usec: 345_000).iso8601(3)
      result =
        graphql(
          query:
            "mutation { createBookmark(input: { targetId: \"#{bookmark_post.id}\", targetType: POST, reminderAt: \"#{reminder}\" }) { success id } }",
        )
      id = result.dig("data", "createBookmark", "id")
      expect(result.dig("data", "createBookmark", "success")).to eq(true)
      expect(Bookmark.find(id).reminder_at.to_r).to eq(Time.iso8601(reminder).to_r)
      node = graphql(query: list_query).dig("data", "bookmarks", "nodes").first
      expect(Time.iso8601(node.fetch("reminderAt"))).to eq(Time.iso8601(reminder))
      query =
        "mutation Rename($input: UpdateBookmarkInput!) { updateBookmark(input: $input) { success } }"
      result =
        graphql(
          query: query,
          variables: {
            input: {
              id: id,
              name: "New note",
              reminderAt: node.fetch("reminderAt"),
              autoDeletePreference: node.fetch("autoDeletePreference"),
            },
          },
        )
      expect(result.dig("data", "updateBookmark", "success")).to eq(true)
      expect(Bookmark.find(id).reminder_at.to_r).to eq(Time.iso8601(reminder).to_r)
    end

    it "preserves the readable automatic deletion preference during a rename" do
      bookmark =
        BookmarkManager.new(user).create_for(
          bookmarkable_id: bookmark_post.id,
          bookmarkable_type: "Post",
          name: "Old name",
          options: {
            auto_delete_preference: Bookmark.auto_delete_preferences[:when_reminder_sent],
          },
        )
      node = graphql(query: list_query).dig("data", "bookmarks", "nodes").first
      query =
        "mutation Rename($input: UpdateBookmarkInput!) { updateBookmark(input: $input) { success } }"
      result =
        graphql(
          query: query,
          variables: {
            input: {
              id: node.fetch("id"),
              name: "New name",
              reminderAt: node.fetch("reminderAt"),
              autoDeletePreference: node.fetch("autoDeletePreference"),
            },
          },
        )
      expect(result.dig("data", "updateBookmark", "success")).to eq(true)
      expect(bookmark.reload.name).to eq("New name")
      expect(bookmark.auto_delete_preference).to eq(
        Bookmark.auto_delete_preferences[:when_reminder_sent],
      )
    end

    it "bounds SQL growth for direct message titles across 20 distinct conversations" do
      SiteSetting.chat_enabled = true
      SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
      SiteSetting.prioritize_username_in_ux = true
      peer_names = []
      20.times do
        peer = Fabricate(:user)
        peer_names << peer.username
        channel = Fabricate(:direct_message_channel, users: [user, peer])
        message = Fabricate(:chat_message, chat_channel: channel)
        BookmarkManager.new(user).create_for(
          bookmarkable_id: message.id,
          bookmarkable_type: "Chat::Message",
        )
      end
      query =
        "query Titles($first: Int!) { bookmarks(first: $first) { nodes { id title fancyTitle autoDeletePreference } } }"
      graphql(query: query, variables: { first: 1 })
      counts =
        [1, 20].map do |limit|
          queries = track_sql_queries { graphql(query: query, variables: { first: limit }) }
          expect(response.parsed_body["errors"]).to be_blank
          nodes = response.parsed_body.dig("data", "bookmarks", "nodes")
          expect(nodes.size).to eq(limit)
          expect(nodes.map { |node| node.fetch("title") }).to all(be_present)
          expect(nodes.map { |node| node.fetch("title") } - peer_names).to be_empty
          expect(nodes.map { |node| node.fetch("title") }).to match_array(peer_names) if limit == 20
          expect(nodes.map { |node| node.fetch("fancyTitle") }).to eq(
            nodes.map { |node| node.fetch("title") },
          )
          queries.size
        end
      expect(counts.last).to be <= counts.first + 2
    end

    it "preserves Data Explorer group context, hidden reports and administrator access" do
      SiteSetting.data_explorer_enabled = true
      group = Fabricate(:group)
      group.add(user)
      report = Fabricate(:query, name: "Visible group report", description: "Report description")
      query_group = Fabricate(:query_group, query: report, group: group)
      result =
        graphql(
          query:
            "mutation { createBookmark(input: { targetType: DATA_EXPLORER_QUERY_GROUP, targetId: \"#{query_group.id}\" }) { success id errors { code } } }",
        )
      expect(result.dig("data", "createBookmark", "success")).to eq(true)
      result = graphql(query: list_query)
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "bookmarks", "nodes").first).to include(
        "targetId" => query_group.id.to_s,
        "title" => report.name,
        "excerpt" => report.description,
        "targetUrl" => "/g/#{group.name}/reports/#{report.id}",
      )

      report.update!(hidden: true)
      expect(graphql(query: list_query).dig("data", "bookmarks", "nodes")).to eq([])
      result =
        graphql(
          query:
            "mutation { createBookmark(input: { targetType: DATA_EXPLORER_QUERY_GROUP, targetId: \"#{query_group.id}\" }) { success errors { code } } }",
        )
      expect(result.dig("data", "createBookmark", "errors", 0, "code")).to eq("FORBIDDEN")
      admin = Fabricate(:admin)
      key = Fabricate(:api_key, user: admin)
      admin_headers = { "Api-Key" => key.key, "Api-Username" => admin.username }
      result =
        graphql(
          query:
            "mutation { createBookmark(input: { targetType: DATA_EXPLORER_QUERY_GROUP, targetId: \"#{query_group.id}\" }) { success } }",
          request_headers: admin_headers,
        )
      expect(result.dig("data", "createBookmark", "success")).to eq(true)
      expect(
        graphql(query: list_query, request_headers: admin_headers)
          .dig("data", "bookmarks", "nodes")
          .first
          .fetch("title"),
      ).to eq(report.name)

      report.update!(hidden: false)
      group.remove(user)
      expect(graphql(query: list_query).dig("data", "bookmarks", "nodes")).to eq([])
      group.add(user)
      query_group.destroy!
      expect(graphql(query: list_query).dig("data", "bookmarks", "nodes")).to eq([])
      replacement = Fabricate(:query_group, query: report, group: group)
      result =
        graphql(
          query:
            "mutation { createBookmark(input: { targetType: DATA_EXPLORER_QUERY_GROUP, targetId: \"#{replacement.id}\" }) { success } }",
          request_headers: admin_headers,
        )
      expect(result.dig("data", "createBookmark", "success")).to eq(true)
      expect(
        graphql(query: list_query, request_headers: admin_headers).dig(
          "data",
          "bookmarks",
          "nodes",
        ).size,
      ).to eq(1)
      SiteSetting.data_explorer_enabled = false
      result =
        graphql(
          query:
            "mutation { createBookmark(input: { targetType: DATA_EXPLORER_QUERY_GROUP, targetId: \"#{replacement.id}\" }) { success errors { code } } }",
        )
      expect(result.dig("data", "createBookmark", "errors", 0, "code")).to eq("BAD_USER_INPUT")
      expect(
        graphql(query: list_query, request_headers: admin_headers).dig(
          "data",
          "bookmarks",
          "nodes",
        ),
      ).to eq([])
    end

    it "bounds SQL growth across 20 Data Explorer reports and group associations" do
      SiteSetting.data_explorer_enabled = true
      names = []
      20.times do
        group = Fabricate(:group)
        group.add(user)
        user.reload
        report = Fabricate(:query)
        names << report.name
        query_group = Fabricate(:query_group, query: report, group: group)
        BookmarkManager.new(user).create_for(
          bookmarkable_id: query_group.id,
          bookmarkable_type: "DiscourseDataExplorer::QueryGroup",
        )
      end
      graphql(query: list_query, variables: { first: 1 })
      counts =
        [1, 20].map do |limit|
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            connection.clear_query_cache
          end
          queries = track_sql_queries { graphql(query: list_query, variables: { first: limit }) }
          expect(response.parsed_body["errors"]).to be_blank
          nodes = response.parsed_body.dig("data", "bookmarks", "nodes")
          expect(nodes.size).to eq(limit)
          expect(nodes.map { |node| node.fetch("title") }).to match_array(names) if limit == 20
          expect(queries).to be_present
          queries.size
        end
      expect(counts.last).to be <= counts.first + 2
    end

    it "bounds SQL growth for 20 bookmarks with distinct topics and authors" do
      20.times do
        target = Fabricate(:post)
        BookmarkManager.new(user).create_for(bookmarkable_id: target.id, bookmarkable_type: "Post")
      end
      graphql(query: list_query, variables: { first: 1 })
      counts =
        [1, 20].map do |limit|
          queries = track_sql_queries { graphql(query: list_query, variables: { first: limit }) }
          expect(response.parsed_body["errors"]).to be_blank
          expect(response.parsed_body.dig("data", "bookmarks", "nodes").size).to eq(limit)
          queries.size
        end
      expect(counts.last).to be <= counts.first + 2
    end
  end

  private

  def graphql(query:, variables: {}, request_headers: headers)
    post "/discourse-graphql/graphql",
         params: {
           query: query,
           variables: variables,
         },
         headers: request_headers,
         as: :json
    response.parsed_body
  end
end
