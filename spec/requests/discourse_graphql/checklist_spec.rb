require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:topic) { Fabricate(:topic, user: user) }
  fab!(:checklist_post) do
    Fabricate(:post, topic: topic, user: user, raw: "- [ ] first item\n- [x] second item")
  end
  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }
  let(:query) do
    "mutation Update($input: ChecklistUpdateInput!) { updateChecklist(input: $input) { success raw cooked updatedAt lastEditorId version revised retryable errors { code message } } }"
  end
  let(:input) do
    {
      postId: checklist_post.id.to_s,
      expectedRaw: checklist_post.raw,
      expectedUpdatedAt: checklist_post.updated_at.iso8601(3),
      mutationId: "graphql-checkbox",
      toggles: [{ checkboxIndex: 0, checkboxSource: "0:0", checked: true }],
    }
  end
  let(:read_query) do
    "query Posts($id: ID!) { topicPosts(topicId: $id) { nodes { id raw cooked updatedAt } } }"
  end

  describe "#execute" do
    before do
      SiteSetting.checklist_enabled = true
      checklist_post.rebake!
    end

    it "creates rendered checklists and echoes a precise read token into native updates" do
      freeze_time(Time.current.change(usec: 345_000) + 1.hour)
      create =
        "mutation Create($input: CreateTopicInput!) { createTopic(input: $input) { status post { id raw cooked updatedAt topic { id } } } }"
      result =
        graphql(
          query: create,
          variables: {
            input: {
              title: "A checklist from the GraphQL client",
              raw: "- [ ] first item\n- [x] second item",
            },
          },
        )
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "createTopic", "status")).to eq("PUBLISHED")
      post_data = result.dig("data", "createTopic", "post")
      expect(post_data.fetch("updatedAt")).to include(".345")
      nodes = Nokogiri::HTML5.fragment(post_data.fetch("cooked")).css("span.chcklst-box")
      expect(nodes.map { |node| node["data-chk-src"] }).to eq(%w[0:0 1:0])
      update =
        input.merge(
          postId: post_data.fetch("id"),
          expectedRaw: post_data.fetch("raw"),
          expectedUpdatedAt: post_data.fetch("updatedAt"),
        )
      result = graphql(query: query, variables: { input: update })
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "updateChecklist")).to include(
        "success" => true,
        "raw" => "- [x] first item\n- [x] second item",
        "revised" => true,
        "lastEditorId" => user.id.to_s,
      )
      read = graphql(query: read_query, variables: { id: post_data.dig("topic", "id") })
      expect(read.dig("data", "topicPosts", "nodes", 0, "raw")).to eq(
        result.dig("data", "updateChecklist", "raw"),
      )
    end

    it "preserves zero and false, native noops, revision effects and cooked correlation" do
      checklist_post.update_columns(
        created_at: 1.hour.ago,
        updated_at: 1.hour.ago,
        last_version_at: 1.hour.ago,
      )
      original_bump = topic.reload.bumped_at
      events = nil
      messages =
        MessageBus.track_publish("/topic/#{topic.id}") do
          events =
            DiscourseEvent.track_events(:post_edited) do
              graphql(query: query, variables: { input: input })
            end
        end
      expect(response.parsed_body.dig("data", "updateChecklist", "success")).to eq(true)
      expect(checklist_post.reload.revisions.count).to eq(1)
      expect(topic.reload.bumped_at.to_r).to eq(original_bump.to_r)
      expect(events).to be_present
      expect(messages.map(&:data).to_json).to include("graphql-checkbox")
      state = response.parsed_body.dig("data", "updateChecklist")
      next_input =
        input.merge(
          expectedRaw: state.fetch("raw"),
          expectedUpdatedAt: state.fetch("updatedAt"),
          toggles: [{ checkboxIndex: 0, checkboxSource: "0:0", checked: false }],
        )
      result = graphql(query: query, variables: { input: next_input })
      expect(result.dig("data", "updateChecklist", "raw")).to eq(
        "- [ ] first item\n- [x] second item",
      )
      state = result.dig("data", "updateChecklist")
      result =
        graphql(
          query: query,
          variables: {
            input:
              next_input.merge(
                expectedRaw: state.fetch("raw"),
                expectedUpdatedAt: state.fetch("updatedAt"),
              ),
          },
        )
      expect(result.dig("data", "updateChecklist")).to include(
        "success" => true,
        "revised" => false,
      )
    end

    it "retains native retryable state conflicts and nonretryable content conflicts" do
      initial = input.deep_dup
      freeze_time(1.second.from_now) do
        PostRevisor.new(checklist_post).revise!(
          user,
          { raw: "- [x] first item\n- [x] second item" },
        )
      end
      result = graphql(query: query, variables: { input: initial })
      expect(result.dig("data", "updateChecklist")).to include(
        "success" => false,
        "retryable" => true,
        "raw" => checklist_post.reload.raw,
        "updatedAt" => checklist_post.updated_at.iso8601(3),
      )
      expect(result.dig("data", "updateChecklist", "errors", 0, "code")).to eq("CONFLICT")
      initial = input.deep_dup
      freeze_time(1.second.from_now) do
        PostRevisor.new(checklist_post).revise!(
          user,
          { raw: "New introduction\n#{checklist_post.raw}" },
        )
      end
      result = graphql(query: query, variables: { input: initial })
      expect(result.dig("data", "updateChecklist")).to include(
        "success" => false,
        "retryable" => false,
        "raw" => checklist_post.reload.raw,
      )
    end

    it "keeps legacy count targets and native permanent checkbox rejection" do
      result =
        graphql(
          query: query,
          variables: {
            input: input.merge(toggles: [{ checkboxIndex: 0, checkboxCount: 2, checked: true }]),
          },
        )
      expect(result.dig("data", "updateChecklist", "success")).to eq(true)
      state = result.dig("data", "updateChecklist")
      result =
        graphql(
          query: query,
          variables: {
            input:
              input.merge(
                expectedRaw: state.fetch("raw"),
                expectedUpdatedAt: state.fetch("updatedAt"),
                toggles: [{ checkboxIndex: 0, checkboxCount: 3, checked: false }],
              ),
          },
        )
      expect(result.dig("data", "updateChecklist", "errors", 0, "code")).to eq("CONFLICT")
      checklist_post.update!(raw: "[X] permanent marker\n[x] second item")
      checklist_post.rebake!
      result =
        graphql(
          query: query,
          variables: {
            input:
              input.merge(
                expectedRaw: checklist_post.reload.raw,
                expectedUpdatedAt: checklist_post.updated_at.iso8601(3),
                toggles: [{ checkboxIndex: 0, checkboxCount: 2, checked: false }],
              ),
          },
        )
      expect(result.dig("data", "updateChecklist", "errors", 0, "code")).to eq("BAD_USER_INPUT")
      expect(checklist_post.reload.raw).to start_with("[X]")
    end

    it "denies anonymous and foreign private edits without exposing conflict state" do
      private_post = Fabricate(:private_message_post, raw: "- [ ] a private checklist item")
      forbidden =
        input.merge(
          postId: private_post.id.to_s,
          expectedRaw: private_post.raw,
          expectedUpdatedAt: private_post.updated_at.iso8601(3),
        )
      result = graphql(query: query, variables: { input: forbidden })
      expect(result.dig("data", "updateChecklist", "errors", 0, "code")).to eq("FORBIDDEN")
      expect(result.dig("data", "updateChecklist", "raw")).to be_nil
      expect(response.body).not_to include(private_post.raw)
      result = graphql(query: query, variables: { input: input }, request_headers: {})
      expect(result.dig("data", "updateChecklist", "errors", 0, "code")).to eq("UNAUTHENTICATED")
    end

    it "retains disabled capability discovery and permitted siblings" do
      SiteSetting.checklist_enabled = false
      result =
        graphql(
          query:
            "mutation Update($input: ChecklistUpdateInput!) { updateChecklist(input: $input) { success } }",
          variables: {
            input: input,
          },
        )
      expect(result.dig("data", "updateChecklist")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FEATURE_DISABLED")
      result = graphql(query: "{ capabilities { id available mutationFields } currentUser { id } }")
      capability =
        result
          .fetch("data")
          .fetch("capabilities")
          .find { |item| item.fetch("id") == "checklist.checkboxChanges" }
      expect(capability).to include("available" => false, "mutationFields" => ["updateChecklist"])
      expect(result.dig("data", "currentUser", "id")).to eq(user.id.to_s)
      freeze_time(1.hour.from_now)
      creation =
        'mutation { createTopic(input: { title: "Checklist rendering while the feature is disabled", raw: "- [ ] A disabled rendering example with enough content" }) { status post { cooked raw } } }'
      result = graphql(query: creation)
      expect(result.dig("data", "createTopic", "status")).to eq("PUBLISHED")
      expect(result.dig("data", "createTopic", "post", "cooked")).not_to include("chcklst-box")
    end

    it "bounds native batches, input failures and query work before writes" do
      invalid = input.merge(toggles: [{ checkboxIndex: -1, checkboxSource: "0:0", checked: true }])
      result = graphql(query: query, variables: { input: invalid })
      expect(result.dig("data", "updateChecklist", "errors", 0, "code")).to eq("BAD_USER_INPUT")
      result =
        graphql(
          query: query,
          variables: {
            input:
              input.merge(
                toggles:
                  51.times.map do |index|
                    { checkboxIndex: index, checkboxCount: 51, checked: true }
                  end,
              ),
          },
        )
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      repeated =
        "mutation Many($input: ChecklistUpdateInput!) { " +
          10
            .times
            .map { |index| "update#{index}: updateChecklist(input: $input) { success }" }
            .join(" ") + " }"
      result = graphql(query: repeated, variables: { input: input })
      expect(result.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
      expect(checklist_post.reload.raw).to eq("- [ ] first item\n- [x] second item")
    end

    it "shares native allowance and preserves GET and readonly protections" do
      RateLimiter.enable
      stub_const(::Checklist::CheckboxesController, :MAX_TOGGLE_REQUESTS_PER_MINUTE, 1) do
        graphql(query: query, variables: { input: input })
        expect(response.parsed_body.dig("data", "updateChecklist", "success")).to eq(true)
        put "/checklist/toggle.json",
            params: {
              post_id: checklist_post.id,
              toggles: [{ checkbox_index: 0, checkbox_source: "0:0", checked: false }],
              expected_raw: checklist_post.reload.raw,
              expected_updated_at: checklist_post.updated_at.iso8601(3),
              mutation_id: "native-request",
            },
            headers: headers
        expect(response.status).to eq(429)
      end
      get "/discourse-graphql/graphql",
          params: {
            query: query,
            variables: { input: input }.to_json,
          },
          headers: headers
      expect(response.status).to eq(400)
      Discourse.enable_readonly_mode
      begin
        graphql(query: query, variables: { input: input })
        expect(response.status).to eq(503)
      ensure
        Discourse.disable_readonly_mode
      end
    end

    it "applies the native 50 item batch with bounded SQL growth" do
      counts =
        [1, 50].map do |count|
          raw = count.times.map { |index| "- [ ] item #{index}" }.join("\n")
          post_record = Fabricate(:post, user: user, raw: raw)
          update =
            input.merge(
              postId: post_record.id.to_s,
              expectedRaw: post_record.raw,
              expectedUpdatedAt: post_record.updated_at.iso8601(3),
              toggles:
                count.times.map do |index|
                  { checkboxIndex: index, checkboxSource: "#{index}:0", checked: true }
                end,
            )
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            connection.clear_query_cache
          end
          queries = track_sql_queries { graphql(query: query, variables: { input: update }) }
          expect(response.parsed_body["errors"]).to be_blank
          expect(response.parsed_body.dig("data", "updateChecklist", "success")).to eq(true)
          expect(post_record.reload.raw.scan("[x]").size).to eq(count)
          queries.size
        end
      expect(counts.last).to be <= counts.first + 2
    end

    it "bounds selected timestamp SQL growth across 50 distinct search results" do
      posts =
        with_search_indexer_enabled do
          50.times.map { Fabricate(:post, raw: "A nebula checklist timestamp observation") }
        end
      query = '{ search(term: "nebula") { id updatedAt } }'
      graphql(query: query)
      counts =
        [1, 50].map do |count|
          SiteSetting.search_page_size = count
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            connection.clear_query_cache
          end
          queries = track_sql_queries { graphql(query: query) }
          expect(response.parsed_body["errors"]).to be_blank
          results = response.parsed_body.dig("data", "search")
          expect(results.size).to eq(count)
          expect(results.map { |result| result.fetch("updatedAt") }).to all(be_present)
          if count == 50
            expect(results.map { |result| result.fetch("id") }).to match_array(
              posts.map { |post| post.id.to_s },
            )
          end
          queries.size
        end
      expect(counts.last).to be <= counts.first + 2
    end

    it "preserves native timestamp inclusion without reading a model fallback" do
      restricted_serializer =
        Class.new(PostSerializer) do
          def include_updated_at?
            false
          end
        end
      stub_const(Object, :PostSerializer, restricted_serializer) do
        result = graphql(query: read_query, variables: { id: topic.id.to_s })
        expect(result["errors"]).to be_blank
        node = result.dig("data", "topicPosts", "nodes", 0)
        expect(node.fetch("updatedAt")).to be_nil
        expect(node.fetch("raw")).to eq(checklist_post.raw)
      end
    end

    it "retains native quote exclusion and updates only the local target" do
      raw =
        "[quote=\"#{user.username}, post:1, topic:#{topic.id}\"]\n- [ ] quoted\n[/quote]\n\n- [ ] local target"
      post_record = Fabricate(:post, user: user, raw: raw)
      update =
        input.merge(
          postId: post_record.id.to_s,
          expectedRaw: post_record.raw,
          expectedUpdatedAt: post_record.updated_at.iso8601(3),
          toggles: [{ checkboxIndex: 0, checkboxSource: "1:0", checked: true }],
        )
      result = graphql(query: query, variables: { input: update })
      expect(result.dig("data", "updateChecklist", "errors", 0, "code")).to eq("CONFLICT")
      expect(post_record.reload.raw).to eq(raw)
      result =
        graphql(
          query: query,
          variables: {
            input:
              update.merge(toggles: [{ checkboxIndex: 0, checkboxSource: "4:0", checked: true }]),
          },
        )
      expect(result.dig("data", "updateChecklist", "success")).to eq(true)
      expect(post_record.reload.raw).to eq(raw.sub("- [ ] local target", "- [x] local target"))
    end

    it "observes current native state across serial mutations" do
      freeze_time(Time.current.change(usec: 345_000))
      checklist_post.update_columns(updated_at: Time.current)
      first = input
      second =
        input.merge(
          expectedRaw: "- [x] first item\n- [x] second item",
          mutationId: "second-checkbox",
          toggles: [{ checkboxIndex: 1, checkboxSource: "1:0", checked: false }],
        )
      mutation =
        "mutation Serial($first: ChecklistUpdateInput!, $second: ChecklistUpdateInput!) { first: updateChecklist(input: $first) { success raw } second: updateChecklist(input: $second) { success raw } }"
      result = graphql(query: mutation, variables: { first: first, second: second })
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "first", "success")).to eq(true)
      expect(result.dig("data", "second", "success")).to eq(true)
      expect(checklist_post.reload.raw).to eq("- [x] first item\n- [ ] second item")
    end

    it "retains browser CSRF before native checkbox changes" do
      sign_in(user)
      ActionController::Base.allow_forgery_protection = true
      begin
        graphql(query: query, variables: { input: input }, request_headers: {})
        expect(response.status).to eq(403)
        expect(checklist_post.reload.raw).to eq(input.fetch(:expectedRaw))
      ensure
        ActionController::Base.allow_forgery_protection = false
      end
    end

    it "rechecks access before returning conflict state after a private category move" do
      result =
        graphql(
          query: query,
          variables: {
            input:
              input.merge(toggles: [{ checkboxIndex: 0, checkboxSource: "0:0", checked: false }]),
          },
        )
      expect(result.dig("data", "updateChecklist", "success")).to eq(true)
      topic.update!(category: Fabricate(:private_category, group: Fabricate(:group)))
      checklist_post.update!(raw: checklist_post.raw + "\nA private edit after the move")
      result = graphql(query: query, variables: { input: input })
      expect(result.dig("data", "updateChecklist", "errors", 0, "code")).to eq("FORBIDDEN")
      expect(result.dig("data", "updateChecklist", "raw")).to be_nil
      expect(response.body).not_to include(checklist_post.reload.raw)
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
