require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user) { Fabricate(:user, created_at: 1.day.ago, last_seen_at: Time.current) }
  fab!(:other_user, :user)
  fab!(:topic) { Fabricate(:topic, user: other_user) }
  fab!(:first_post) { Fabricate(:post, topic: topic, user: other_user) }
  fab!(:last_post) { Fabricate(:post, topic: topic, user: other_user) }
  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }
  let(:state_query) do
    "{ topic(id: \"#{topic.id}\") { currentUserState { lastReadPostNumber notificationLevel totalTimeViewedMs } } }"
  end

  describe "#execute" do
    it "records native reading time, notification updates and current actor state" do
      notification =
        Fabricate(:notification, user: user, topic: topic, post_number: last_post.post_number)
      result = graphql(query: state_query)
      expect(result.dig("data", "topic", "currentUserState")).to be_nil
      query =
        "mutation { recordTopicTimings(input: { topicId: \"#{topic.id}\", topicTimeMs: 500, timings: [{ postNumber: #{last_post.post_number}, milliseconds: 250 }] }) { success errors { code } } }"
      publications = MessageBus.track_publish("/notification/#{user.id}") { graphql(query: query) }
      expect(response.parsed_body.dig("data", "recordTopicTimings", "success")).to eq(true)
      expect(
        PostTiming.find_by(user: user, topic: topic, post_number: last_post.post_number).msecs,
      ).to eq(250)
      expect(notification.reload.read).to eq(true)
      expect(publications).to be_present
      result = graphql(query: state_query)
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "topic", "currentUserState")).to include(
        "lastReadPostNumber" => last_post.post_number,
        "totalTimeViewedMs" => 0,
      )
      graphql(query: query)
      expect(
        PostTiming.find_by(user: user, topic: topic, post_number: last_post.post_number).msecs,
      ).to eq(500)
      expect(
        graphql(query: state_query).dig("data", "topic", "currentUserState", "totalTimeViewedMs"),
      ).to eq(500)
      expect(TopicUser.find_by(user: other_user, topic: topic)&.last_read_post_number).not_to eq(
        last_post.post_number,
      )
    end

    it "retains native timing caps and ignores post numbers above the native range" do
      Fabricate(:topic_user, user: user, topic: topic, total_msecs_viewed: 0)
      SiteSetting.whispers_allowed_groups = Group::AUTO_GROUPS[:staff].to_s
      whisper = Fabricate(:post, topic: topic, post_type: Post.types[:whisper])
      result =
        graphql(
          query:
            "mutation { recordTopicTimings(input: { topicId: \"#{topic.id}\", topicTimeMs: 999999, timings: [{ postNumber: #{last_post.post_number}, milliseconds: 999999 }, { postNumber: #{whisper.post_number}, milliseconds: 100 }, { postNumber: 9999, milliseconds: 100 }] }) { success } }",
        )
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "recordTopicTimings", "success")).to eq(true)
      expect(PostTiming.where(user: user, topic: topic).pluck(:post_number, :msecs)).to eq(
        [[last_post.post_number, 60_000]],
      )
      expect(TopicUser.find_by(user: user, topic: topic).last_read_post_number).to eq(
        last_post.post_number,
      )
      expect(TopicUser.find_by(user: user, topic: topic).total_msecs_viewed).to eq(60_000)
    end

    it "keeps the GraphQL response when the outer server supports socket hijacking" do
      calls = []
      graphql(
        query:
          "mutation { recordTopicTimings(input: { topicId: \"#{topic.id}\", topicTimeMs: 100, timings: [{ postNumber: #{first_post.post_number}, milliseconds: 100 }] }) { success } }",
        request_env: {
          "rack.hijack" => -> do
            calls << :hijacked
            raise "Nested response stole the socket"
          end,
        },
      )
      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.dig("data", "recordTopicTimings", "success")).to eq(true)
      expect(calls).to be_empty
      expect(PostTiming.exists?(user: user, topic: topic)).to eq(true)
    end

    it "rechecks private access for all state changes" do
      private_topic = Fabricate(:private_message_topic, user: user)
      private_post = Fabricate(:post, topic: private_topic)
      TopicAllowedUser.where(user: user, topic: private_topic).delete_all
      operations = [
        "recordTopicTimings(input: { topicId: \"#{private_topic.id}\", topicTimeMs: 100, timings: [{ postNumber: #{private_post.post_number}, milliseconds: 100 }] })",
        "updateTopicNotifications(topicId: \"#{private_topic.id}\", level: WATCHING)",
        "resetTopicReading(topicId: \"#{private_topic.id}\")",
      ]
      operations.each do |operation|
        result = graphql(query: "mutation { #{operation} { success errors { code } } }")
        payload = result.fetch("data").values.first
        expect(payload.fetch("success")).to eq(false)
        expect(payload.dig("errors", 0, "code")).to eq("NOT_FOUND")
      end
      expect(PostTiming.where(user: user, topic: private_topic)).to be_empty
      expect(TopicUser.find_by(user: user, topic: private_topic)).to be_nil
    end

    it "updates notification preferences with native publication and events" do
      events =
        DiscourseEvent.track_events do
          publications =
            MessageBus.track_publish("/topic/#{topic.id}") do
              graphql(
                query:
                  "mutation { updateTopicNotifications(topicId: \"#{topic.id}\", level: WATCHING) { success errors { code } } }",
              )
            end
          expect(publications).to include(
            have_attributes(
              data: include(notification_level_change: TopicUser.notification_levels[:watching]),
            ),
          )
        end
      expect(response.parsed_body.dig("data", "updateTopicNotifications", "success")).to eq(true)
      expect(events).to include(
        include(event_name: :topic_notification_level_changed, params: [3, user.id, topic.id]),
      )
      result = graphql(query: state_query)
      expect(result.dig("data", "topic", "currentUserState", "notificationLevel")).to eq("WATCHING")
      expect(TopicUser.find_by(user: other_user, topic: topic)&.notification_level).not_to eq(3)

      graphql(
        query:
          "mutation { updateTopicNotifications(topicId: \"#{topic.id}\", level: MUTED) { success } }",
      )
      expect(TopicUser.find_by(user: user, topic: topic).notification_level).to eq(0)
      graphql(
        query:
          "mutation { updateTopicNotifications(topicId: \"#{topic.id}\", level: REGULAR) { success } }",
      )
      expect(
        graphql(query: state_query).dig("data", "topic", "currentUserState", "notificationLevel"),
      ).to eq("REGULAR")
    end

    it "resets only the last post or all reading state through native actions" do
      graphql(
        query:
          "mutation { recordTopicTimings(input: { topicId: \"#{topic.id}\", topicTimeMs: 100, timings: [{ postNumber: #{first_post.post_number}, milliseconds: 50 }, { postNumber: #{last_post.post_number}, milliseconds: 50 }] }) { success } }",
      )
      notification =
        Fabricate(
          :notification,
          user: user,
          topic: topic,
          post_number: last_post.post_number,
          read: true,
        )
      result =
        graphql(
          query:
            "mutation { resetTopicReading(topicId: \"#{topic.id}\", lastPostOnly: true) { success errors { code } } }",
        )
      expect(result.dig("data", "resetTopicReading", "success")).to eq(true)
      expect(PostTiming.where(user: user, topic: topic).pluck(:post_number)).to eq(
        [first_post.post_number],
      )
      expect(notification.reload.read).to eq(false)
      expect(TopicUser.find_by(user: user, topic: topic).last_read_post_number).to eq(
        last_post.post_number - 1,
      )

      result =
        graphql(query: "mutation { resetTopicReading(topicId: \"#{topic.id}\") { success } }")
      expect(result.dig("data", "resetTopicReading", "success")).to eq(true)
      expect(PostTiming.where(user: user, topic: topic)).to be_empty
      expect(TopicUser.find_by(user: user, topic: topic)).to be_nil
    end

    it "retains native private message reading and reset publication" do
      private_topic = Fabricate(:private_message_topic, user: user)
      post = Fabricate(:post, topic: private_topic)
      result =
        graphql(
          query:
            "mutation { recordTopicTimings(input: { topicId: \"#{private_topic.id}\", topicTimeMs: 100, timings: [{ postNumber: #{post.post_number}, milliseconds: 100 }] }) { success } }",
        )
      expect(result.dig("data", "recordTopicTimings", "success")).to eq(true)
      expect(TopicUser.find_by(user: user, topic: private_topic).last_read_post_number).to eq(
        post.post_number,
      )
      publications =
        MessageBus.track_publish("/private-message-topic-tracking-state/user/#{user.id}") do
          graphql(
            query: "mutation { resetTopicReading(topicId: \"#{private_topic.id}\") { success } }",
          )
        end
      expect(response.parsed_body.dig("data", "resetTopicReading", "success")).to eq(true)
      expect(publications).to be_present
    end

    it "rejects invalid timing shapes and excessive work before writes" do
      invalid = [
        { topicTimeMs: -1, timings: [] },
        { topicTimeMs: 100, timings: [{ postNumber: -1, milliseconds: 1 }] },
        { topicTimeMs: 100, timings: [{ postNumber: 0, milliseconds: 1 }] },
        { topicTimeMs: 100, timings: [{ postNumber: 1, milliseconds: -1 }] },
        {
          topicTimeMs: 100,
          timings: [{ postNumber: 1, milliseconds: 1 }, { postNumber: 1, milliseconds: 1 }],
        },
        {
          topicTimeMs: 100,
          timings: 51.times.map { |index| { postNumber: index + 1, milliseconds: 1 } },
        },
      ]
      query =
        "mutation Timings($input: TopicTimingsInput!) { recordTopicTimings(input: $input) { success errors { code } } }"
      invalid.each do |input|
        result = graphql(query: query, variables: { input: input.merge(topicId: topic.id.to_s) })
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
      selections =
        10.times.map do |index|
          "watch#{index}: updateTopicNotifications(topicId: \"#{topic.id}\", level: WATCHING) { success }"
        end
      graphql(query: "mutation { #{selections.join(" ")} }")
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
      expect(TopicUser.find_by(user: user, topic: topic)).to be_nil
      expect(PostTiming.where(user: user, topic: topic)).to be_empty
    end

    it "preserves mutation login, GET and readonly protections" do
      query =
        "mutation { updateTopicNotifications(topicId: \"#{topic.id}\", level: WATCHING) { success errors { code } } }"
      result = graphql(query: query, request_headers: {})
      expect(result.dig("data", "updateTopicNotifications", "errors", 0, "code")).to eq(
        "UNAUTHENTICATED",
      )
      get "/discourse-graphql/graphql", params: { query: query }, headers: headers
      expect(response.status).to eq(400)
      Discourse.enable_readonly_mode
      begin
        graphql(query: query)
        expect(response.status).to eq(503)
        expect(TopicUser.find_by(user: user, topic: topic)).to be_nil
      ensure
        Discourse.disable_readonly_mode
      end
    end

    it "loads only current actor state in one batch across 50 topics" do
      topics = [topic] + Fabricate.times(49, :topic)
      topics.each do |entry|
        TopicUser.change(
          user,
          entry.id,
          notification_level: TopicUser.notification_levels[:watching],
        )
        TopicUser.change(
          other_user,
          entry.id,
          notification_level: TopicUser.notification_levels[:muted],
        )
      end
      query =
        "query States($limit: Int!) { latestTopics(limit: $limit) { id currentUserState { notificationLevel lastReadPostNumber } } }"
      graphql(query: query, variables: { limit: 1 })
      counts =
        [1, 50].map do |limit|
          queries = track_sql_queries { graphql(query: query, variables: { limit: limit }) }
          expect(response.parsed_body["errors"]).to be_blank
          nodes = response.parsed_body.dig("data", "latestTopics")
          expect(nodes.size).to eq(limit)
          expect(nodes.map { |entry| entry.dig("currentUserState", "notificationLevel") }).to all(
            eq("WATCHING"),
          )
          queries.size
        end
      expect(counts.last).to be <= counts.first + 2
      expect(
        graphql(query: state_query, request_headers: {}).dig("data", "topic", "currentUserState"),
      ).to be_nil
    end
  end

  private

  def graphql(query:, variables: {}, request_headers: headers, request_env: {})
    post "/discourse-graphql/graphql",
         params: {
           query: query,
           variables: variables,
         },
         headers: request_headers,
         env: request_env,
         as: :json
    response.parsed_body
  end
end
