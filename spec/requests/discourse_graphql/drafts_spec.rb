require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user, :user)
  fab!(:other_user, :user)
  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }
  let(:save_query) { 'mutation Save($input: SaveDraftInput!) { saveDraft(input: $input) { success sequence conflictUser { id username name } errors { code description } } }' }
  let(:read_query) { 'query Read($key: String!, $sequence: BigInt) { draft(key: $key, sequence: $sequence) { key sequence content { reply title action categoryId postId whisper originalText originalTitle tags { id name format } originalTags { id name format } unmappedFields } } }' }
  let(:list_query) { 'query Drafts($first: Int, $after: String) { drafts(first: $first, after: $after) { nodes { key sequence title slug categoryId displayUsername displayName draftUsername content { reply title } } pageInfo { endCursor hasNextPage } } }' }

  describe "#execute" do
    it "saves typed composer content with native sequence, owner, events and reading" do
      input = { key: "new_topic", sequence: 0, owner: "client-one", content: { reply: "My draft reply", title: "My draft topic", action: "createTopic", categoryId: 1, whisper: false, tags: [{ name: "native-tag", format: "NAME" }] } }
      events = DiscourseEvent.track_events(:draft_saved) { graphql(query: save_query, variables: { input: input }) }
      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.dig("data", "saveDraft", "success")).to eq(true)
      expect(response.parsed_body.dig("data", "saveDraft", "sequence")).to eq("0")
      draft = Draft.find_by(user: user, draft_key: "new_topic")
      expect(draft.owner).to eq("client-one")
      expect(draft.parsed_data).to include("reply" => "My draft reply", "categoryId" => 1, "whisper" => false, "tags" => ["native-tag"])
      expect(events.first.fetch(:params)).to eq([user, "new_topic", draft.parsed_data])
      result = graphql(query: read_query, variables: { key: "new_topic" })
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "draft", "content")).to include("reply" => "My draft reply", "whisper" => false, "tags" => [{ "id" => nil, "name" => "native-tag", "format" => "NAME" }], "unmappedFields" => [])
      expect(user.user_stat.reload.draft_count).to eq(1)
    end

    it "retains sequence conflicts, explicit force save and owner handover" do
      first = { key: "versioned", sequence: 0, owner: "first-client", content: { reply: "First revision" } }
      graphql(query: save_query, variables: { input: first })
      graphql(query: save_query, variables: { input: first.merge(owner: "second-client", content: { reply: "Second revision" }) })
      expect(response.parsed_body.dig("data", "saveDraft", "sequence")).to eq("1")
      events = DiscourseEvent.track_events(:draft_saved) { graphql(query: save_query, variables: { input: first }) }
      expect(response.parsed_body.dig("data", "saveDraft", "success")).to eq(false)
      expect(response.parsed_body.dig("data", "saveDraft", "errors", 0)).to include("code" => "CONFLICT", "description" => I18n.t("draft.sequence_conflict_error.description"))
      expect(events).to be_empty
      expect(Draft.find_by(user: user, draft_key: "versioned").parsed_data["reply"]).to eq("Second revision")
      result = graphql(query: save_query, variables: { input: first.merge(forceSave: true) })
      expect(result.dig("data", "saveDraft", "sequence")).to eq("2")
      expect(Draft.find_by(user: user, draft_key: "versioned").owner).to eq("first-client")
      result = graphql(query: read_query, variables: { key: "versioned", sequence: 1 })
      expect(result.dig("data", "draft")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("CONFLICT")
    end

    it "round trips native bigint sequence values without losing precision" do
      sequence = 2**40
      DraftSequence.create!(user_id: user.id, draft_key: "big-sequence", sequence: sequence)
      Draft.set(user, "big-sequence", sequence, { reply: "Large sequence" }.to_json)
      result = graphql(query: read_query, variables: { key: "big-sequence" })
      expect(result.dig("data", "draft", "sequence")).to eq(sequence.to_s)
      result = graphql(query: save_query, variables: { input: { key: "big-sequence", sequence: sequence.to_s, content: { reply: "Updated sequence" } } })
      expect(result.dig("data", "saveDraft", "sequence")).to eq((sequence + 1).to_s)
      expect(DraftSequence.current(user, "big-sequence")).to eq(sequence + 1)
      result = graphql(query: save_query, variables: { input: { key: "big-sequence", sequence: (2**63).to_s, content: {} } })
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      expect(DraftSequence.current(user, "big-sequence")).to eq(sequence + 1)
    end

    it "keeps the native recovery for a missing draft and current sequence" do
      DraftSequence.next!(user, "recovered")
      result = graphql(query: save_query, variables: { input: { key: "recovered", sequence: 0, content: { reply: "Recovered content" } } })
      expect(result.dig("data", "saveDraft", "sequence")).to eq("1")
      result = graphql(query: read_query, variables: { key: "missing" })
      expect(result.dig("data", "draft")).to eq("key" => "missing", "sequence" => "0", "content" => nil)
    end

    it "preserves tag object identity and native edit conflict information" do
      post = Fabricate(:post, user: user)
      tag = Fabricate(:tag)
      post.topic.tags = [tag]
      content = { postId: post.id, action: "edit", originalText: post.raw, originalTitle: post.topic.title, originalTags: [{ id: tag.id, name: tag.name, format: "OBJECT" }] }
      input = { key: "topic_#{post.topic_id}", sequence: 0, content: content }
      result = graphql(query: save_query, variables: { input: input })
      expect(result.dig("data", "saveDraft", "success")).to eq(true)
      expect(result.dig("data", "saveDraft", "conflictUser")).to be_nil
      expect(Draft.find_by(user: user, draft_key: input[:key]).parsed_data["original_tags"]).to eq([{ "id" => tag.id, "name" => tag.name }])
      result = graphql(query: save_query, variables: { input: input.merge(content: content.merge(originalText: "Stale original")) })
      expect(result.dig("data", "saveDraft", "success")).to eq(true)
      expect(result.dig("data", "saveDraft", "conflictUser", "id")).to eq(post.last_editor.id.to_s)
    end

    it "keeps private references from revealing native topic or conflict metadata" do
      private_post = Fabricate(:private_message_post)
      key = "topic_#{private_post.topic_id}"
      result = graphql(query: save_query, variables: { input: { key: key, sequence: 0, content: { postId: private_post.id, originalText: "Stale text", action: "edit", reply: "My own saved note" } } })
      expect(result.dig("data", "saveDraft", "success")).to eq(true)
      expect(result.dig("data", "saveDraft", "conflictUser")).to be_nil
      result = graphql(query: list_query)
      expect(result["errors"]).to be_blank
      node = result.dig("data", "drafts", "nodes").first
      expect(node).to include("title" => nil, "slug" => nil, "categoryId" => nil, "displayUsername" => user.username)
      expect(node.dig("content", "reply")).to eq("My own saved note")
      expect(result.to_json).not_to include(private_post.topic.title, private_post.user.username)
      SiteSetting.enable_names = false
      expect(graphql(query: list_query).dig("data", "drafts", "nodes", 0, "displayName")).to be_nil
    end

    it "isolates actors and reports unmapped draft fields without returning arbitrary values" do
      Draft.set(user, "shared-key", 0, { reply: "My note", plugin_secret: "unmapped secret", metaData: { custom_flag: true } }.to_json)
      Draft.set(other_user, "shared-key", 0, { reply: "Another user's note" }.to_json)
      result = graphql(query: read_query, variables: { key: "shared-key" })
      expect(result.dig("data", "draft", "content", "reply")).to eq("My note")
      expect(result.dig("data", "draft", "content", "unmappedFields")).to include("plugin_secret", "metaData")
      expect(result.to_json).not_to include("unmapped secret", "Another user's note")
      Draft.set(user, "legacy", 0, '"legacy scalar"')
      result = graphql(query: read_query, variables: { key: "legacy" })
      expect(result.dig("data", "draft", "content", "unmappedFields")).to eq(["$format"])
    end

    it "reports unmapped metadata even when its stored value is empty" do
      Draft.set(user, "empty-metadata", 0, { reply: "My note", metaData: {} }.to_json)
      result = graphql(query: read_query, variables: { key: "empty-metadata" })
      expect(result.dig("data", "draft", "content", "unmappedFields")).to eq(["metaData"])
    end

    it "bounds unmapped field reporting and avoids truncating oversize legacy tags silently" do
      unknown = 110.times.to_h { |index| ["plugin_#{index}", "unmapped value"] }
      Draft.set(user, "unmapped", 0, unknown.merge("tags" => 101.times.map { |index| "tag#{index}" }).to_json)
      result = graphql(query: read_query, variables: { key: "unmapped" })
      content = result.dig("data", "draft", "content")
      expect(content.fetch("tags")).to be_nil
      expect(content.fetch("unmappedFields").size).to eq(100)
      expect(content.fetch("unmappedFields")).to include("$more")
      expect(result.to_json).not_to include("unmapped value", "tag100")
    end

    it "contains the native legacy array listing failure and permits explicit lookup and deletion" do
      Draft.set(user, "array-root", 0, "[]")
      result = graphql(query: read_query, variables: { key: "array-root" })
      expect(result.dig("data", "draft", "content", "unmappedFields")).to eq(["$format"])
      result = graphql(query: '{ drafts { nodes { key } } currentUser { id } }')
      expect(result.dig("data", "drafts")).to be_nil
      expect(result.dig("data", "currentUser", "id")).to eq(user.id.to_s)
      expect(result.dig("errors", 0, "extensions", "code")).to eq("INTERNAL_ERROR")
      expect(result.to_json).not_to include("postId", "TypeError", "Draft.preload_data")
      result = graphql(query: 'mutation { deleteDraft(key: "array-root", sequence: 0) { success } }')
      expect(result.dig("data", "deleteDraft", "success")).to eq(true)
      expect(graphql(query: list_query).dig("data", "drafts", "nodes")).to eq([])
    end

    it "retains native backup work before stale sequence rejection" do
      SiteSetting.backup_drafts_to_pm_length = 5
      input = { key: "backup-key", sequence: 0, content: { reply: "Original backup content" } }
      graphql(query: save_query, variables: { input: input })
      graphql(query: save_query, variables: { input: input.merge(content: { reply: "Latest accepted content" }) })
      result = graphql(query: save_query, variables: { input: input.merge(content: { reply: "Rejected save backup content" }) })
      expect(result.dig("data", "saveDraft", "errors", 0, "code")).to eq("CONFLICT")
      expect(Draft.find_by(user: user, draft_key: "backup-key").parsed_data["reply"]).to eq("Latest accepted content")
      backup = BackupDraftPost.find_by(user: user, key: "backup-key")
      expect(backup.post.raw).to include("Rejected save backup content")
      expect(backup.post.topic.private_message?).to eq(true)
    end

    it "retains native length and count limits while allowing an existing draft update" do
      SiteSetting.max_drafts_per_user = 1
      graphql(query: save_query, variables: { input: { key: "first", sequence: 0, content: { reply: "One" } } })
      result = graphql(query: save_query, variables: { input: { key: "second", sequence: 0, content: { reply: "Two" } } })
      expect(result.dig("data", "saveDraft", "errors", 0, "code")).to eq("FORBIDDEN")
      result = graphql(query: save_query, variables: { input: { key: "first", sequence: 0, content: { reply: "Updated" } } })
      expect(result.dig("data", "saveDraft", "sequence")).to eq("1")
      SiteSetting.max_draft_length = 500
      result = graphql(query: save_query, variables: { input: { key: "first", sequence: 1, content: { reply: "x" * 501 } } })
      expect(result.dig("data", "saveDraft", "errors", 0, "code")).to eq("BAD_USER_INPUT")
      expect(Draft.find_by(user: user, draft_key: "first").parsed_data["reply"]).to eq("Updated")
    end

    it "retains native upload references and clears them through draft deletion" do
      upload = Fabricate(:upload, user: user)
      input = { key: "with-upload", sequence: 0, content: { reply: "![image](#{upload.short_url})" } }
      graphql(query: save_query, variables: { input: input })
      expect(response.parsed_body.dig("data", "saveDraft", "success")).to eq(true)
      draft = Draft.find_by(user: user, draft_key: "with-upload")
      expect(UploadReference.exists?(target: draft, upload: upload)).to eq(true)
      result = graphql(query: 'mutation { deleteDraft(key: "with-upload", sequence: 0) { success errors { code } } }')
      expect(result.dig("data", "deleteDraft", "success")).to eq(true)
      expect(Draft.exists?(draft.id)).to eq(false)
      expect(UploadReference.exists?(target_type: "Draft", target_id: draft.id)).to eq(false)
    end

    it "retains stale single deletion acknowledgement and preexisting bulk conflict rejection" do
      Draft.set(user, "one", 0, { reply: "First" }.to_json)
      Draft.set(user, "one", 0, { reply: "Latest" }.to_json)
      Draft.set(user, "two", 0, { reply: "Second" }.to_json)
      result = graphql(query: 'mutation { deleteDraft(key: "one", sequence: 0) { success } }')
      expect(result.dig("data", "deleteDraft", "success")).to eq(true)
      expect(Draft.exists?(user: user, draft_key: "one")).to eq(true)
      query = 'mutation Delete($drafts: [DraftReferenceInput!]!) { deleteDrafts(drafts: $drafts) { success deletedCount errors { code } } }'
      result = graphql(query: query, variables: { drafts: [{ key: "one", sequence: 0 }, { key: "two", sequence: 0 }] })
      expect(result.dig("data", "deleteDrafts", "errors", 0, "code")).to eq("CONFLICT")
      expect(Draft.where(user: user).count).to eq(2)
      result = graphql(query: query, variables: { drafts: [{ key: "one", sequence: 1 }, { key: "two", sequence: 0 }] })
      expect(result.dig("data", "deleteDrafts", "deletedCount")).to eq(2)
      expect(user.user_stat.reload.draft_count).to eq(0)
    end

    it "preserves native administrative target checks for single and bulk deletion" do
      Draft.set(other_user, "target", 0, { reply: "Other draft" }.to_json)
      query = 'mutation Target($username: String!) { deleteDraft(key: "target", sequence: 0, username: $username) { success errors { code } } }'
      result = graphql(query: query, variables: { username: other_user.username })
      expect(result.dig("data", "deleteDraft", "errors", 0, "code")).to eq("FORBIDDEN")
      admin = Fabricate(:admin)
      key = Fabricate(:api_key, user: admin)
      result = graphql(query: query, variables: { username: other_user.username }, request_headers: { "Api-Key" => key.key, "Api-Username" => admin.username })
      expect(result.dig("data", "deleteDraft", "success")).to eq(true)
      expect(Draft.exists?(user: other_user, draft_key: "target")).to eq(false)
      Draft.set(other_user, "target", 0, { reply: "Other draft" }.to_json)
      sign_in(admin)
      result = graphql(query: query, variables: { username: other_user.username }, request_headers: {})
      expect(result.dig("data", "deleteDraft", "errors", 0, "code")).to eq("FORBIDDEN")
      result = graphql(query: 'mutation Target($username: String!) { deleteDrafts(drafts: [{ key: "target", sequence: 0 }], username: $username) { success deletedCount } }', variables: { username: other_user.username }, request_headers: { "Api-Key" => key.key, "Api-Username" => admin.username })
      expect(result.dig("data", "deleteDrafts", "deletedCount")).to eq(1)
    end

    it "paginates native ordering and binds continuation to actor and size" do
      3.times do |index|
        Draft.set(user, "draft-#{index}", 0, { reply: "Draft #{index}" }.to_json)
        Draft.find_by(user: user, draft_key: "draft-#{index}").update!(updated_at: (index + 1).minutes.ago)
      end
      result = graphql(query: list_query, variables: { first: 2 })
      expect(result.dig("data", "drafts", "nodes").map { |node| node.fetch("key") }).to eq(%w[draft-0 draft-1])
      cursor = result.dig("data", "drafts", "pageInfo", "endCursor")
      result = graphql(query: list_query, variables: { first: 2, after: cursor })
      expect(result.dig("data", "drafts", "nodes").map { |node| node.fetch("key") }).to eq(["draft-2"])
      expect(result.dig("data", "drafts", "pageInfo")).to eq("endCursor" => nil, "hasNextPage" => false)
      [{ first: 1, after: cursor }, { first: 0 }, { first: 51 }, { after: "invalid" }].each do |variables|
        result = graphql(query: list_query, variables: variables)
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
      key = Fabricate(:api_key, user: other_user)
      result = graphql(query: list_query, variables: { first: 2, after: cursor }, request_headers: { "Api-Key" => key.key, "Api-Username" => other_user.username })
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
    end

    it "rejects excessive input and write work before persistence" do
      invalid = [
        { key: "x" * 41, sequence: 0, content: {} },
        { key: "invalid", sequence: -1, content: {} },
        { key: "invalid", sequence: 0, content: { tags: 101.times.map { |index| { name: "tag#{index}", format: "NAME" } } } },
      ]
      invalid.each do |input|
        result = graphql(query: save_query, variables: { input: input })
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
      references = 31.times.map { |index| { key: "draft#{index}", sequence: 0 } }
      result = graphql(query: 'mutation Delete($drafts: [DraftReferenceInput!]!) { deleteDrafts(drafts: $drafts) { success } }', variables: { drafts: references })
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      selections = 10.times.map { |index| "save#{index}: saveDraft(input: { key: \"key#{index}\", sequence: 0, content: {} }) { success }" }
      graphql(query: "mutation { #{selections.join(" ")} }")
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
      expect(Draft.where(user: user)).to be_empty
    end

    it "retains login, GET and readonly protections" do
      result = graphql(query: '{ drafts { nodes { key } } currentUser { id } }', request_headers: {})
      expect(result.dig("data", "drafts")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("UNAUTHENTICATED")
      query = 'mutation { saveDraft(input: { key: "new_topic", sequence: 0, content: { reply: "Draft" } }) { success errors { code } } }'
      result = graphql(query: query, request_headers: {})
      expect(result.dig("data", "saveDraft", "errors", 0, "code")).to eq("UNAUTHENTICATED")
      get "/discourse-graphql/graphql", params: { query: query }, headers: headers
      expect(response.status).to eq(400)
      Discourse.enable_readonly_mode
      begin
        graphql(query: query)
        expect(response.status).to eq(503)
      ensure
        Discourse.disable_readonly_mode
      end
      expect(Draft.where(user: user)).to be_empty
    end

    it "bounds SQL growth across 50 drafts with distinct permitted topic and post authors" do
      authors = []
      50.times do
        post = Fabricate(:post)
        authors << post.user.username
        Draft.set(user, "topic_#{post.topic_id}", 0, { postId: post.id, reply: "My draft reply" }.to_json)
      end
      graphql(query: list_query, variables: { first: 1 })
      counts = [1, 50].map do |limit|
        ActiveRecord::Base.connection_pool.with_connection { |connection| connection.clear_query_cache }
        queries = track_sql_queries { graphql(query: list_query, variables: { first: limit }) }
        expect(response.parsed_body["errors"]).to be_blank
        nodes = response.parsed_body.dig("data", "drafts", "nodes")
        expect(nodes.size).to eq(limit)
        expect(nodes.map { |node| node.fetch("displayUsername") }).to all(be_present)
        expect(nodes.map { |node| node.fetch("displayUsername") }).to match_array(authors) if limit == 50
        expect(nodes.map { |node| node.fetch("title") }).to all(be_present)
        expect(queries).to be_present
        queries.size
      end
      expect(counts.last).to be <= counts.first + 2
    end
  end

  private

  def graphql(query:, variables: {}, request_headers: headers)
    post "/discourse-graphql/graphql", params: { query: query, variables: variables }, headers: request_headers, as: :json
    response.parsed_body
  end
end
