require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user, :user)
  fab!(:other_user, :user)
  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }
  let(:page_query) do
    "query Notifications($first: Int, $after: String, $filter: NotificationFilter) { notifications(first: $first, after: $after, filter: $filter) { nodes { id notificationType read createdAt topicId postNumber fancyTitle slug actingUserName actingUserAvatarTemplate } seenNotificationId pageInfo { endCursor hasNextPage } } }"
  end

  describe "#execute" do
    it "reads native current actor notifications through bounded pages" do
      notifications =
        3.times.map do |index|
          Fabricate(
            :notification,
            user: user,
            created_at: (3 - index).minutes.ago,
            data: { topic_title: "A notification", display_username: other_user.username }.to_json,
          )
        end
      Fabricate(:notification, user: other_user)
      get "/notifications.json", params: { limit: 2 }, headers: headers
      native = response.parsed_body.fetch("notifications")

      result = graphql(query: page_query, variables: { first: 2 })
      expect(result["errors"]).to be_blank
      nodes = result.dig("data", "notifications", "nodes")
      expect(nodes.map { |node| node.fetch("id") }).to eq(
        native.map { |node| node.fetch("id").to_s },
      )
      nodes
        .zip(native)
        .each do |node, original|
          expect(node.fetch("notificationType")).to eq(original.fetch("notification_type"))
          expect(node.fetch("fancyTitle")).to eq(original["fancy_title"])
          expect(node.fetch("actingUserAvatarTemplate")).to eq(
            original["acting_user_avatar_template"],
          )
        end
      cursor = result.dig("data", "notifications", "pageInfo", "endCursor")
      result = graphql(query: page_query, variables: { first: 2, after: cursor })
      expect(result.dig("data", "notifications", "nodes").map { |node| node.fetch("id") }).to eq(
        [notifications.first.id.to_s],
      )
      expect(result.dig("data", "notifications", "pageInfo")).to eq(
        "endCursor" => nil,
        "hasNextPage" => false,
      )
    end

    it "continues past a page filtered entirely by native access checks" do
      private_topic = Fabricate(:private_message_topic)
      Fabricate(:notification, user: user, topic: private_topic, created_at: 1.minute.ago)
      visible = Fabricate(:notification, user: user, created_at: 2.minutes.ago)
      result = graphql(query: page_query, variables: { first: 1 })
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "notifications", "nodes")).to eq([])
      cursor = result.dig("data", "notifications", "pageInfo", "endCursor")
      expect(cursor).to be_present
      result = graphql(query: page_query, variables: { first: 1, after: cursor })
      expect(result.dig("data", "notifications", "nodes").map { |node| node.fetch("id") }).to eq(
        [visible.id.to_s],
      )
    end

    it "retains native reviewable and disabled badge filtering" do
      reviewable = Fabricate(:reviewable_flagged_post)
      Fabricate(
        :notification,
        user: user,
        data: { reviewable_id: reviewable.id, topic_title: "Private review" }.to_json,
      )
      badge = Fabricate(:badge, enabled: true)
      awarded =
        Fabricate(
          :notification,
          user: user,
          notification_type: Notification.types[:granted_badge],
          data: { badge_id: badge.id }.to_json,
        )
      visible = Fabricate(:notification, user: user)
      result = graphql(query: page_query)
      expect(result["errors"]).to be_blank
      expect(
        result.dig("data", "notifications", "nodes").map { |node| node.fetch("id") },
      ).to contain_exactly(awarded.id.to_s, visible.id.to_s)

      badge.update!(enabled: false)
      result = graphql(query: page_query)
      expect(result.dig("data", "notifications", "nodes").map { |node| node.fetch("id") }).to eq(
        [visible.id.to_s],
      )
      SiteSetting.enable_badges = false
      result = graphql(query: page_query)
      expect(result.dig("data", "notifications", "nodes").map { |node| node.fetch("id") }).to eq(
        [visible.id.to_s],
      )
    end

    it "preserves read filters and rejects altered pagination context" do
      Fabricate(:notification, user: user, read: true)
      Fabricate.times(2, :notification, user: user, read: false)
      result = graphql(query: page_query, variables: { first: 1, filter: "UNREAD" })
      expect(result.dig("data", "notifications", "nodes").map { |node| node.fetch("read") }).to eq(
        [false],
      )
      cursor = result.dig("data", "notifications", "pageInfo", "endCursor")
      [
        { first: 2, filter: "UNREAD", after: cursor },
        { first: 1, filter: "READ", after: cursor },
        { after: "invalid" },
        { first: 0 },
        { first: 51 },
      ].each do |variables|
        result = graphql(query: page_query, variables: variables)
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
      other_key = Fabricate(:api_key, user: other_user)
      result =
        graphql(
          query: page_query,
          variables: {
            first: 1,
            filter: "UNREAD",
            after: cursor,
          },
          request_headers: {
            "Api-Key" => other_key.key,
            "Api-Username" => other_user.username,
          },
        )
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      result = graphql(query: page_query, variables: { filter: "READ", first: nil })
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "notifications", "nodes").map { |node| node.fetch("read") }).to eq(
        [true],
      )
    end

    it "rechecks private topic access on continuation and protects anonymous siblings" do
      topic = Fabricate(:private_message_topic, user: user)
      Fabricate(:notification, user: user, topic: topic, created_at: 2.minutes.ago)
      Fabricate(:notification, user: user, created_at: 1.minute.ago)
      result = graphql(query: page_query, variables: { first: 1 })
      cursor = result.dig("data", "notifications", "pageInfo", "endCursor")
      TopicAllowedUser.where(topic: topic, user: user).delete_all
      result = graphql(query: page_query, variables: { first: 1, after: cursor })
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "notifications", "nodes")).to eq([])
      result =
        graphql(query: "{ notifications { nodes { id } } currentUser { id } }", request_headers: {})
      expect(result.dig("data", "notifications")).to be_nil
      expect(result.dig("data", "currentUser")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("UNAUTHENTICATED")
    end

    it "marks only the current actor notification and publishes native state" do
      user.update!(last_seen_at: Time.current)
      notification = Fabricate(:notification, user: user, read: false)
      foreign = Fabricate(:notification, user: other_user, read: false)
      events =
        MessageBus.track_publish("/notification/#{user.id}") do
          graphql(
            query:
              "mutation { markNotificationRead(id: \"#{notification.id}\") { success errors { code } } foreign: markNotificationRead(id: \"#{foreign.id}\") { success } missing: markNotificationRead(id: \"0\") { success } }",
          )
        end
      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.dig("data", "markNotificationRead", "success")).to eq(true)
      expect(response.parsed_body.dig("data", "foreign", "success")).to eq(true)
      expect(response.parsed_body.dig("data", "missing", "success")).to eq(true)
      expect(notification.reload.read).to eq(true)
      expect(foreign.reload.read).to eq(false)
      expect(events).to be_present
      result = graphql(query: page_query, variables: { filter: "READ" })
      expect(result.dig("data", "notifications", "nodes").map { |node| node.fetch("id") }).to eq(
        [notification.id.to_s],
      )
    end

    it "marks notifications without a type filter and bumps only the current actor seen state" do
      own =
        %i[mentioned replied].map do |type|
          Fabricate(
            :notification,
            user: user,
            notification_type: Notification.types.fetch(type),
            read: false,
          )
        end
      foreign = Fabricate(:notification, user: other_user, read: false)
      graphql(query: "mutation { markAllNotificationsRead { success errors { code } } }")
      expect(response.parsed_body.dig("data", "markAllNotificationsRead", "success")).to eq(true)
      expect(own.map { |notification| notification.reload.read }).to eq([true, true])
      expect(foreign.reload.read).to eq(false)
      expect(user.reload.seen_notification_id).to eq(own.last.id)
      expect(other_user.reload.seen_notification_id).to eq(0)
    end

    it "requires mutation authentication and rejects excess work before reading updates" do
      notification = Fabricate(:notification, user: user, read: false)
      query =
        "mutation { markNotificationRead(id: \"#{notification.id}\") { success errors { code } } }"
      result = graphql(query: query, request_headers: {})
      expect(result.dig("data", "markNotificationRead", "errors", 0, "code")).to eq(
        "UNAUTHENTICATED",
      )
      get "/discourse-graphql/graphql", params: { query: query }, headers: headers
      expect(response.status).to eq(400)
      selections = 3.times.map { |index| "all#{index}: markAllNotificationsRead { success }" }
      graphql(query: "mutation { #{selections.join(" ")} }")
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
      expect(notification.reload.read).to eq(false)
    end

    it "bounds SQL growth across 50 notifications with distinct topics and actors" do
      SiteSetting.show_user_menu_avatars = true
      50.times do
        actor = Fabricate(:user)
        Fabricate(
          :notification,
          user: user,
          data: { topic_title: "A notification", display_username: actor.username }.to_json,
        )
      end
      graphql(query: page_query, variables: { first: 1 })
      counts =
        [1, 50].map do |limit|
          queries = track_sql_queries { graphql(query: page_query, variables: { first: limit }) }
          expect(response.parsed_body["errors"]).to be_blank
          expect(response.parsed_body.dig("data", "notifications", "nodes").size).to eq(limit)
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
