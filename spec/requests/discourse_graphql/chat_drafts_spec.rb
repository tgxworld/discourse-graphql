require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:channel, :category_channel)
  fab!(:thread) { Fabricate(:chat_thread, channel: channel) }

  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    channel.add(user)
  end

  describe "#execute" do
    it "preserves native serialized composer state and replaces only the addressed draft" do
      content = '{ "message": "Hello 👋", "uploads": [{"id":9}], "future": {"value":false} }'
      result = update_draft(data: content)
      expect(result.dig("data", "updateChatChannelDraft")).to eq("success" => true, "errors" => [])
      channel_draft = Chat::Draft.find_by!(user: user, chat_channel: channel, thread_id: nil)
      expect(channel_draft.data).to eq(content)
      result = update_draft(data: "Native serialized thread state", thread_id: thread.id)
      expect(result.dig("data", "updateChatThreadDraft")).to eq("success" => true, "errors" => [])
      thread_draft = Chat::Draft.find_by!(user: user, chat_channel: channel, thread_id: thread.id)
      expect(thread_draft.data).to eq("Native serialized thread state")

      result = update_draft(data: "Replacement")

      expect(result.dig("data", "updateChatChannelDraft", "success")).to eq(true)
      expect(channel_draft.reload.data).to eq("Replacement")
      expect(thread_draft.reload.data).to eq("Native serialized thread state")
      expect(Chat::Draft.where(user: user, chat_channel: channel).count).to eq(2)
    end

    it "retains native null and blank clearing without crossing channel or thread scope" do
      [nil, "", "   "].each do |blank|
        update_draft(data: "Channel")
        update_draft(data: "Thread", thread_id: thread.id)
        result = update_draft(data: blank)
        expect(result.dig("data", "updateChatChannelDraft", "success")).to eq(true)
        expect(Chat::Draft.where(user: user, chat_channel: channel, thread_id: nil)).not_to exist
        expect(Chat::Draft.find_by!(user: user, chat_channel: channel, thread_id: thread.id).data).to eq("Thread")
        result = update_draft(data: blank, thread_id: thread.id)
        expect(result.dig("data", "updateChatThreadDraft", "success")).to eq(true)
        expect(Chat::Draft.where(user: user, chat_channel: channel)).not_to exist
      end
    end

    it "isolates actor writes and native read windows" do
      update_draft(data: "First actor state")
      other = Fabricate(:user, refresh_auto_groups: true)
      other_key = Fabricate(:api_key, user: other)
      other_headers = { "Api-Key" => other_key.key, "Api-Username" => other.username }
      result = update_draft(data: "Second actor state", request_headers: other_headers)
      expect(result.dig("data", "updateChatChannelDraft", "success")).to eq(true)

      result = drafts

      expect(result["errors"]).to be_blank
      expect(result.dig("data", "currentUserChatDrafts", "nodes")).to eq([
        { "channelId" => channel.id.to_s, "threadId" => nil, "serializedData" => "First actor state" },
      ])
      expect(Chat::Draft.find_by!(user: other, chat_channel: channel).data).to eq("Second actor state")
    end

    it "traverses exactly the native recent window with stable serialized data and order" do
      entries = Array.new(21) do |index|
        draft_channel = Fabricate(:category_channel)
        Chat::Draft.create!(user: user, chat_channel: draft_channel, data: "Stored #{index}", updated_at: index.minutes.ago)
      end
      get "/session/current.json", headers: headers
      expect(response.status).to eq(200)
      native = response.parsed_body.fetch("current_user").fetch("chat_drafts")
      expect(native.size).to eq(20)
      cursor = nil
      pages = 3.times.map do
        result = drafts(first: 7, after: cursor)
        expect(result["errors"]).to be_blank
        page = result.dig("data", "currentUserChatDrafts")
        cursor = page.dig("pageInfo", "endCursor")
        page
      end

      expected = native.map do |entry|
        { "channelId" => entry.fetch("channel_id").to_s, "threadId" => entry["thread_id"]&.to_s, "serializedData" => entry.fetch("data") }
      end
      expect(pages.flat_map { |page| page.fetch("nodes") }).to eq(expected)
      expect(pages.map { |page| page.fetch("windowSize") }).to eq([20, 20, 20])
      expect(pages.map { |page| page.dig("pageInfo", "hasNextPage") }).to eq([true, true, false])
      expect(pages.last.dig("pageInfo", "endCursor")).to be_nil
      expect(pages.to_s).not_to include(entries.last.data)
    end

    it "distinguishes an empty native window from omitted personal Chat data" do
      result = drafts
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "currentUserChatDrafts")).to eq("nodes" => [], "windowSize" => 0, "pageInfo" => { "endCursor" => nil, "hasNextPage" => false })
      update_draft(data: "Saved before disabling")
      user.user_option.update!(chat_enabled: false)

      result = drafts

      expect(result["errors"]).to be_blank
      expect(result.dig("data", "currentUserChatDrafts")).to be_nil
      expect(result.dig("data", "currentUser", "id")).to eq(user.id.to_s)
      user.user_option.update!(chat_enabled: true)
      SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:staff]
      expect(drafts.dig("data", "currentUserChatDrafts")).to be_nil
    end

    it "retains own native saved drafts after private access loss while denying changes" do
      group = Fabricate(:group)
      group.add(user)
      private_channel = Fabricate(:private_category_channel, group: group)
      update_draft(channel_id: private_channel.id, data: "Own private draft")
      draft = Chat::Draft.find_by!(user: user, chat_channel: private_channel)
      group.remove(user)
      get "/session/current.json", headers: headers
      native = response.parsed_body.dig("current_user", "chat_drafts")
      expect(native.map { |entry| entry.fetch("data") }).to include(draft.data)
      result = drafts
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "currentUserChatDrafts", "nodes").map { |entry| entry.fetch("serializedData") }).to include(draft.data)

      result = update_draft(channel_id: private_channel.id, data: nil)

      expect(result.dig("data", "updateChatChannelDraft", "success")).to eq(false)
      expect(result.dig("data", "updateChatChannelDraft", "errors", 0, "code")).to eq("FORBIDDEN")
      expect(draft.reload.data).to eq("Own private draft")
    end

    it "retains native missing channel and thread binding errors" do
      other_channel = Fabricate(:category_channel)
      [[-999, nil, "updateChatChannelDraft"], [channel.id, -999, "updateChatThreadDraft"], [other_channel.id, thread.id, "updateChatThreadDraft"]].each do |channel_id, thread_id, field|
        result = update_draft(channel_id: channel_id, thread_id: thread_id, data: "Denied")
        expect(result.dig("data", field, "success")).to eq(false)
        expect(result.dig("data", field, "errors", 0, "code")).to eq("NOT_FOUND")
      end
      expect(Chat::Draft.where(user: user)).not_to exist
    end

    it "preserves native readonly category and Chat eligibility denial" do
      group = Fabricate(:group, users: [user])
      category = Fabricate(:private_category, group: group, permission_type: CategoryGroup.permission_types[:readonly])
      readonly_channel = Fabricate(:category_channel, chatable: category)
      result = update_draft(channel_id: readonly_channel.id, data: "Denied")
      expect(result.dig("data", "updateChatChannelDraft", "errors", 0, "code")).to eq("FORBIDDEN")
      SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:staff]
      result = update_draft(data: "Denied")
      expect(result.dig("data", "updateChatChannelDraft", "errors", 0, "code")).to eq("FORBIDDEN")
      expect(Chat::Draft.where(user: user)).not_to exist
    end

    it "retains native character length checks without replacing existing state" do
      SiteSetting.max_chat_draft_length = 10
      result = update_draft(data: "👋" * 10)
      expect(result.dig("data", "updateChatChannelDraft", "success")).to eq(true)
      draft = Chat::Draft.find_by!(user: user, chat_channel: channel)

      result = update_draft(data: "👋" * 11)

      expect(result.dig("data", "updateChatChannelDraft", "success")).to eq(false)
      expect(result.dig("data", "updateChatChannelDraft", "errors", 0, "code")).to eq("BAD_USER_INPUT")
      expect(draft.reload.data).to eq("👋" * 10)
    end

    it "invalidates content bound cursors and rejects changed context and page bounds" do
      update_draft(data: "Channel")
      update_draft(data: "Thread", thread_id: thread.id)
      cursor = drafts(first: 1).dig("data", "currentUserChatDrafts", "pageInfo", "endCursor")
      expect(cursor).to be_present
      [{ first: 0 }, { first: 21 }, { after: "invalid" }, { after: "x" * 16_385 }, { first: 2, after: cursor }].each do |arguments|
        result = drafts(**arguments)
        expect(result.dig("data", "currentUserChatDrafts")).to be_nil
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
      other = Fabricate(:user, refresh_auto_groups: true)
      other_key = Fabricate(:api_key, user: other)
      result = drafts(first: 1, after: cursor, request_headers: { "Api-Key" => other_key.key, "Api-Username" => other.username })
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      update_draft(data: "Changed")
      result = drafts(first: 1, after: cursor)
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
    end

    it "rejects continuation when native draft visibility is withdrawn" do
      update_draft(data: "Channel")
      update_draft(data: "Thread", thread_id: thread.id)
      cursor = drafts(first: 1).dig("data", "currentUserChatDrafts", "pageInfo", "endCursor")
      expect(cursor).to be_present
      user.user_option.update!(chat_enabled: false)

      result = drafts(first: 1, after: cursor)

      expect(result.dig("data", "currentUserChatDrafts")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
    end

    it "retains native field omission and skips unrelated current user renderers" do
      update_draft(data: "Native state")
      restricted = Class.new(CurrentUserSerializer) do
        def unread_notifications
          raise "Unselected notification renderer unavailable"
        end
      end
      stub_const(Object, :CurrentUserSerializer, restricted) do
        result = drafts
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "currentUserChatDrafts", "nodes", 0, "serializedData")).to eq("Native state")
      end
      omitted = Class.new(CurrentUserSerializer) do
        def include_chat_drafts?
          false
        end
      end
      stub_const(Object, :CurrentUserSerializer, omitted) do
        result = drafts
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "currentUserChatDrafts")).to be_nil
      end
    end

    it "rejects excessive read breadth and mutation aliases before persistence" do
      fields = 11.times.map { |index| "a#{index}: updateChatChannelDraft(channelId: \"#{channel.id}\", serializedData: \"Denied\") { success }" }.join(" ")
      post "/discourse-graphql/graphql", params: { query: "mutation { #{fields} }" }, headers: headers, as: :json
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
      expect(Chat::Draft.where(user: user)).not_to exist
      fields = 11.times.map { |index| "a#{index}: currentUserChatDrafts(first: 20) { nodes { serializedData } }" }.join(" ")
      get "/discourse-graphql/graphql", params: { query: "{ #{fields} }" }, headers: headers
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
    end

    it "preserves serial mutation updates and clears inside one operation" do
      query = <<~GRAPHQL
        mutation {
          first: updateChatChannelDraft(channelId: "#{channel.id}", serializedData: "First") { success }
          second: updateChatChannelDraft(channelId: "#{channel.id}", serializedData: "Second") { success }
          clear: updateChatThreadDraft(channelId: "#{channel.id}", threadId: "#{thread.id}") { success }
        }
      GRAPHQL
      update_draft(data: "Thread", thread_id: thread.id)
      post "/discourse-graphql/graphql", params: { query: query }, headers: headers, as: :json
      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.fetch("data").values).to eq([{ "success" => true }] * 3)
      expect(Chat::Draft.find_by!(user: user, chat_channel: channel, thread_id: nil).data).to eq("Second")
      expect(Chat::Draft.where(user: user, thread_id: thread.id)).not_to exist
      expect(drafts.dig("data", "currentUserChatDrafts", "nodes", 0, "serializedData")).to eq("Second")
    end

    it "preserves browser CSRF protection and accepts a native session header token" do
      sign_in(user)
      get "/session/csrf.json"
      token = response.parsed_body.fetch("csrf")
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      begin
        update_draft(data: "Denied", request_headers: {})
        expect(response.status).to eq(403)
        expect(Chat::Draft.where(user: user)).not_to exist
        result = update_draft(data: "Session saved", request_headers: { "X-CSRF-Token" => token, "X-Requested-With" => "XMLHttpRequest" })
        expect(result.dig("data", "updateChatChannelDraft", "success")).to eq(true)
        expect(Chat::Draft.find_by!(user: user, chat_channel: channel).data).to eq("Session saved")
      ensure
        ActionController::Base.allow_forgery_protection = original
      end
    end

    it "preserves readonly, archived and read credential restrictions" do
      Discourse.enable_readonly_mode
      begin
        update_draft(data: "Denied")
        expect(response.status).to eq(503)
      ensure
        Discourse.disable_readonly_mode
      end
      SiteSetting.site_archived = true
      begin
        update_draft(data: "Denied")
        expect(response.status).to eq(503)
      ensure
        SiteSetting.site_archived = false
      end
      api_key.update!(scope_mode: :read_only, api_key_scopes: [ApiKeyScope.new(resource: "global", action: "read")])
      expect(drafts["errors"]).to be_blank
      update_draft(data: "Denied")
      expect(response.status).to eq(403)
      expect(Chat::Draft.where(user: user)).not_to exist
    end

    it "retains anonymous native lookup and mutation denial" do
      get "/session/current.json"
      expect(response.status).to eq(404)
      result = drafts(request_headers: {})
      expect(result.dig("data", "currentUserChatDrafts")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
      result = update_draft(data: "Denied", request_headers: {})
      expect(result.dig("data", "updateChatChannelDraft", "success")).to eq(false)
      expect(result.dig("data", "updateChatChannelDraft", "errors", 0, "code")).to eq("UNAUTHENTICATED")
      expect(Chat::Draft.where(user: user)).not_to exist
    end

    it "keeps disabled Chat nullable and preserves core siblings" do
      SiteSetting.chat_enabled = false
      result = drafts
      expect(result.dig("data", "currentUserChatDrafts")).to be_nil
      expect(result.dig("data", "currentUser", "id")).to eq(user.id.to_s)
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FEATURE_DISABLED")
      result = update_draft(data: "Denied")
      expect(result.dig("data", "updateChatChannelDraft")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FEATURE_DISABLED")
      expect(Chat::Draft.where(user: user)).not_to exist
    end
  end

  private

  def update_draft(data:, channel_id: channel.id, thread_id: nil, request_headers: headers)
    field = thread_id.nil? ? "updateChatChannelDraft" : "updateChatThreadDraft"
    arguments = "channelId: #{channel_id.to_s.to_json}, serializedData: #{data.to_json}"
    arguments += ", threadId: #{thread_id.to_s.to_json}" unless thread_id.nil?
    query = "mutation { #{field}(#{arguments}) { success errors { code message } } }"
    post "/discourse-graphql/graphql", params: { query: query }, headers: request_headers, as: :json
    response.parsed_body
  end

  def drafts(first: 20, after: nil, request_headers: headers)
    query = <<~GRAPHQL
      query Drafts($first: Int, $after: String) {
        currentUserChatDrafts(first: $first, after: $after) {
          nodes { channelId threadId serializedData }
          windowSize
          pageInfo { endCursor hasNextPage }
        }
        currentUser { id }
      }
    GRAPHQL
    get "/discourse-graphql/graphql", params: { query: query, variables: { first: first, after: after }.to_json }, headers: request_headers
    response.parsed_body
  end
end
