require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category) }
  fab!(:original_post) { Fabricate(:post, topic: topic) }

  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }
  let(:input) do
    {
      title: "A detailed observation from the community",
      raw: "This is a detailed observation with enough content to start a discussion.",
      categoryId: category.id,
    }
  end
  let(:query) { <<~GRAPHQL }
      mutation Create($input: CreateTopicInput!) {
        createTopic(input: $input) {
          status
          action
          post { id raw topic { id fancyTitle } }
          errors { code message retryAfterSeconds }
          pendingCount
        }
      }
    GRAPHQL

  describe "#execute" do
    it "creates a discussion that can be read through the API" do
      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               input: input,
             },
           },
           headers: headers,
           as: :json

      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      result = response.parsed_body.fetch("data").fetch("createTopic")
      expect(result.fetch("status")).to eq("PUBLISHED")
      expect(result.fetch("errors")).to eq([])
      expect(result.dig("post", "raw")).to eq(input.fetch(:raw))
      topic_id = result.dig("post", "topic", "id")
      expect(topic_id).to be_present

      get "/discourse-graphql/graphql",
          params: {
            query: "query { topic(id: \"#{topic_id}\") { fancyTitle } }",
          },
          headers: headers

      expect(response.parsed_body.dig("data", "topic", "fancyTitle")).to eq(input.fetch(:title))
    end

    it "retains native approval queues instead of publishing restricted posts" do
      SiteSetting.approve_unless_allowed_groups = Group::AUTO_GROUPS[:trust_level_4]

      expect do
        post "/discourse-graphql/graphql",
             params: {
               query: query,
               variables: {
                 input: input,
               },
             },
             headers: headers,
             as: :json
      end.to change { ReviewableQueuedPost.where(target_created_by: user).count }.by(1)

      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      result = response.parsed_body.fetch("data").fetch("createTopic")
      expect(result.fetch("status")).to eq("PENDING")
      expect(result.fetch("action")).to eq("enqueued")
      expect(result.fetch("post")).to be_nil
      expect(result.fetch("pendingCount")).to be > 0
      expect(result.fetch("errors")).to eq([])
      expect(Topic.find_by(title: input.fetch(:title))).to be_nil
    end

    it "returns typed native validation errors without creating a discussion" do
      expect do
        post "/discourse-graphql/graphql",
             params: {
               query: query,
               variables: {
                 input: input.merge(raw: "a"),
               },
             },
             headers: headers,
             as: :json
      end.not_to change(Post, :count)

      expect(response.status).to eq(200)
      result = response.parsed_body.fetch("data").fetch("createTopic")
      expect(result.fetch("status")).to eq("FAILED")
      expect(result.fetch("post")).to be_nil
      expect(result.fetch("errors").map { |error| error.fetch("code") }).to all(
        eq("BAD_USER_INPUT"),
      )
      expect(result.fetch("errors")).to be_present
    end

    it "keeps anonymous actors from publishing" do
      expect do
        post "/discourse-graphql/graphql",
             params: {
               query: query,
               variables: {
                 input: input,
               },
             },
             as: :json
      end.not_to change(Post, :count)

      expect(response.status).to eq(200)
      result = response.parsed_body.fetch("data").fetch("createTopic")
      expect(result.fetch("status")).to eq("FAILED")
      expect(result.fetch("errors").map { |error| error.fetch("code") }).to include(
        "UNAUTHENTICATED",
      )
    end

    it "preserves native API retry memoization" do
      post_ids =
        2.times.map do
          post "/discourse-graphql/graphql",
               params: {
                 query: query,
                 variables: {
                   input: input,
                 },
               },
               headers: headers,
               as: :json

          expect(response.status).to eq(200)
          expect(response.parsed_body.dig("data", "createTopic", "status")).to eq("PUBLISHED")
          response.parsed_body.dig("data", "createTopic", "post", "id")
        end

      expect(post_ids.uniq.size).to eq(1)
      expect(Topic.where(title: input.fetch(:title)).count).to eq(1)
    end

    it "refreshes loaded state between serial reply mutations" do
      mutation = <<~GRAPHQL
        mutation {
          first: createPost(input: {topicId: "#{topic.id}", raw: "The first detailed reply to this discussion."}) {
            status post { id topic { postsCount } } errors { code }
          }
          second: createPost(input: {topicId: "#{topic.id}", raw: "The second detailed reply to this discussion."}) {
            status post { id topic { postsCount } } errors { code }
          }
        }
      GRAPHQL

      post "/discourse-graphql/graphql", params: { query: mutation }, headers: headers

      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      result = response.parsed_body.fetch("data")
      expect(result.dig("first", "status")).to eq("PUBLISHED")
      expect(result.dig("second", "status")).to eq("PUBLISHED")
      expect(result.dig("second", "post", "topic", "postsCount")).to eq(
        result.dig("first", "post", "topic", "postsCount") + 1,
      )
    end

    it "keeps notification clearing owned by the outer request" do
      user.update!(last_seen_at: Time.current)
      notification = Fabricate(:notification, user: user)
      mutation = <<~GRAPHQL
        mutation {
          first: createPost(input: {topicId: "#{topic.id}", raw: "The first reply while clearing a notification."}) { status }
          second: createPost(input: {topicId: "#{topic.id}", raw: "The second reply while clearing a notification."}) { status }
        }
      GRAPHQL

      messages =
        MessageBus.track_publish("/notification/#{user.id}") do
          post "/discourse-graphql/graphql",
               params: {
                 query: mutation,
               },
               headers: headers.merge("Discourse-Clear-Notifications" => notification.id.to_s)
        end

      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.fetch("data").values.map { |entry| entry.fetch("status") }).to eq(
        %w[PUBLISHED PUBLISHED],
      )
      expect(notification.reload.read).to eq(true)
      expect(messages.size).to eq(1)
    end

    it "retains browser session rotation through the actual response cookie" do
      sign_in(user)
      original_cookie = cookies[Auth::DefaultCurrentUserProvider::TOKEN_COOKIE]
      freeze_time(Time.current + UserAuthToken::ROTATE_TIME + 1.minute)

      events =
        DiscourseEvent.track_events(:user_session_refreshed) do
          post "/discourse-graphql/graphql",
               params: {
                 query: query,
                 variables: {
                   input: input,
                 },
               },
               as: :json
        end

      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("data", "createTopic", "status")).to eq("PUBLISHED")
      expect(events.size).to eq(1)
      expect(cookies[Auth::DefaultCurrentUserProvider::TOKEN_COOKIE]).not_to eq(original_cookie)

      get "/discourse-graphql/graphql", params: { query: "query { currentUser { id } }" }
      expect(response.parsed_body.dig("data", "currentUser", "id")).to eq(user.id.to_s)
    end

    it "preserves native creation rate limits and retry guidance" do
      user.update!(created_at: 2.days.ago)
      RateLimiter.enable
      SiteSetting.max_topics_per_day = 1

      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               input: input,
             },
           },
           headers: headers,
           as: :json
      expect(response.parsed_body.dig("data", "createTopic", "status")).to eq("PUBLISHED")

      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               input: input.merge(title: "A second detailed observation from the community"),
             },
           },
           headers: headers,
           as: :json

      expect(response.status).to eq(200)
      result = response.parsed_body.fetch("data").fetch("createTopic")
      expect(result.fetch("status")).to eq("FAILED")
      expect(result.fetch("errors").map { |error| error.fetch("code") }).to include("RATE_LIMITED")
      expect(result.fetch("errors").first.fetch("retryAfterSeconds")).to be > 0
    end

    it "keeps native readonly rejection at the transport boundary" do
      Discourse.enable_readonly_mode

      expect do
        post "/discourse-graphql/graphql",
             params: {
               query: query,
               variables: {
                 input: input,
               },
             },
             headers: headers,
             as: :json
      end.not_to change(Post, :count)

      expect(response.status).to eq(503)
    ensure
      Discourse.disable_readonly_mode
    end

    it "ignores native bypass flags outside the typed input" do
      expect do
        post "/discourse-graphql/graphql",
             params: {
               query: query,
               variables: {
                 input: input.merge(raw: "a"),
               },
               skip_validations: true,
               import_mode: true,
             },
             headers: headers,
             as: :json
      end.not_to change(Post, :count)

      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("data", "createTopic", "status")).to eq("FAILED")
    end

    it "rejects excessive native creation work before publishing any post" do
      selections = 10.times.map { |index| <<~GRAPHQL }
            topic#{index}: createTopic(input: {
              title: "A detailed community observation number #{index}",
              raw: "A detailed and unique observation number #{index} with enough content for a discussion."
            }) { status }
          GRAPHQL

      expect do
        post "/discourse-graphql/graphql",
             params: {
               query: "mutation { #{selections.join(" ")} }",
             },
             headers: headers
      end.not_to change(Post, :count)

      expect(response.status).to eq(200)
      expect(
        response.parsed_body.fetch("errors").map { |error| error.dig("extensions", "code") },
      ).to include("QUERY_TOO_COMPLEX")
      expect(response.parsed_body["data"]).to be_blank
    end

    context "with browser CSRF verification" do
      before do
        sign_in(user)
        ActionController::Base.allow_forgery_protection = true
      end

      after { ActionController::Base.allow_forgery_protection = false }

      it "requires a valid token and accepts the native session token" do
        expect do
          post "/discourse-graphql/graphql",
               params: {
                 query: query,
                 variables: {
                   input: input,
                 },
               },
               as: :json
        end.not_to change(Post, :count)
        expect(response.status).to eq(403)

        sign_in(user)
        get "/session/csrf.json"
        token = response.parsed_body.fetch("csrf")
        post "/discourse-graphql/graphql",
             params: {
               query: query,
               variables: {
                 input: input,
               },
             },
             headers: {
               "X-CSRF-Token" => token,
             },
             as: :json

        expect(response.status).to eq(200)
        expect(response.parsed_body.dig("data", "createTopic", "status")).to eq("PUBLISHED")
      end
    end
  end
end
