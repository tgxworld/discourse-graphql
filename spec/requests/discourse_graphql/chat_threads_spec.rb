require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:other_user, :user)
  fab!(:channel) { Fabricate(:category_channel, threading_enabled: true) }
  fab!(:thread) { Fabricate(:chat_thread, channel: channel, original_message_user: other_user) }
  fab!(:reply) { Fabricate(:chat_message, chat_channel: channel, thread: thread) }

  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    channel.add(user)
    thread.update!(last_message: reply)
  end

  describe "#execute" do
    it "reads native thread metadata and distinct original and preview shapes without joining" do
      get "/chat/api/channels/#{channel.id}/threads/#{thread.id}.json", headers: headers
      expect(response.status).to eq(200)
      native = response.parsed_body.fetch("thread")
      result = lookup
      expect(result["errors"]).to be_blank
      value = result.dig("data", "chatThread")
      expect(value).to include("id" => thread.id.to_s, "title" => native["title"], "status" => native.fetch("status").upcase, "channelId" => channel.id.to_s, "replyCount" => native.fetch("reply_count").to_s, "lastMessageId" => reply.id.to_s, "force" => native.fetch("force"), "currentUserMembership" => nil)
      expect(value.fetch("originalMessage")).to include("id" => thread.original_message_id.to_s, "raw" => native.dig("original_message", "message"), "cooked" => native.dig("original_message", "cooked"), "channelId" => channel.id.to_s, "author" => { "id" => other_user.id.to_s, "username" => other_user.username })
      expect(value.dig("preview", "lastReplyId")).to eq(reply.id.to_s)
      expect(value.dig("preview", "lastReplyExcerpt")).to eq(native.dig("preview", "last_reply_excerpt"))
      expect(value.dig("preview", "participantCount")).to eq(native.dig("preview", "participant_count").to_s)
      expect(value.dig("meta", "messageBusLastIds", "threadMessageBusLastId")).to eq(native.dig("meta", "message_bus_last_ids", "thread_message_bus_last_id").to_s)
      expect(thread.membership_for(user)).to be_nil
    end

    it "reads native membership after a control while preserving its read position" do
      actor_membership = thread.add(user, notification_level: 3)
      actor_membership.update!(last_read_message_id: thread.original_message_id, thread_title_prompt_seen: true)
      result = lookup
      expect(result.dig("data", "chatThread", "currentUserMembership")).to eq("threadId" => thread.id.to_s, "notificationLevel" => "WATCHING", "lastReadMessageId" => thread.original_message_id.to_s, "threadTitlePromptSeen" => true)
      expect(actor_membership.reload.last_read_message_id).to eq(thread.original_message_id)
    end

    it "preserves native missing original author and JSON timestamp precision" do
      thread.original_message.update_columns(user_id: nil, created_at: Time.zone.parse("2026-01-01T10:20:30.345678Z"))
      get "/chat/api/channels/#{channel.id}/threads/#{thread.id}.json", headers: headers
      expect(response.status).to eq(200)
      native = response.parsed_body.dig("thread", "original_message")
      result = lookup(selection: "originalMessage { author { id username } createdAt }")
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatThread", "originalMessage", "author")).to eq(native["user"])
      expect(result.dig("data", "chatThread", "originalMessage", "createdAt")).to eq(native.fetch("created_at"))
    end

    it "retains native root serializer omissions and unselected renderer isolation" do
      restricted = Class.new(Chat::ThreadSerializer) do
        def initialize(object, options = {})
          super(object, options.merge(only: [:id]))
        end
      end
      stub_const(Chat, :ThreadSerializer, restricted) do
        result = lookup
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "chatThread").except("id").values).to all(be_nil)
      end
      Chat::ThreadSerializer.any_instance.stubs(:preview).raises("Preview unavailable")
      result = lookup(selection: "id title")
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatThread", "id")).to eq(thread.id.to_s)
      result = lookup(selection: "preview { lastReplyId }")
      expect(result.dig("errors", 0, "extensions", "code")).to eq("INTERNAL_ERROR")
    end

    it "pages native mentioned users and rejects changed message context or page size" do
      actors = Fabricate.times(3, :user)
      actors.reverse_each { |actor| Fabricate(:user_chat_mention, chat_message: thread.original_message, user: actor) }
      result = lookup(selection: "originalMessage { mentionedUsers(first: 1) { nodes { id username } totalCount pageInfo { endCursor hasNextPage } } }")
      page = result.dig("data", "chatThread", "originalMessage", "mentionedUsers")
      expect(page).to include("nodes" => [{ "id" => actors.first.id.to_s, "username" => actors.first.username }], "totalCount" => "3")
      cursor = page.dig("pageInfo", "endCursor")
      expect(cursor).to be_present
      result = lookup(selection: "originalMessage { mentionedUsers(first: 1, after: #{cursor.to_json}) { nodes { id } } }")
      expect(result.dig("data", "chatThread", "originalMessage", "mentionedUsers", "nodes")).to eq([{ "id" => actors.second.id.to_s }])
      result = lookup(selection: "originalMessage { mentionedUsers(first: 2, after: #{cursor.to_json}) { nodes { id } } }")
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      Chat::UserMention.where(user: actors.last, chat_message: thread.original_message).delete_all
      result = lookup(selection: "originalMessage { mentionedUsers(first: 1, after: #{cursor.to_json}) { nodes { id } } }")
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
    end

    it "retains native anonymous public lookup and private revocation boundaries" do
      SiteSetting.chat_allowed_groups = "#{Group::AUTO_GROUPS[:everyone]}|#{Group::AUTO_GROUPS[:anonymous_users]}"
      result = lookup(request_headers: {})
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatThread", "id")).to eq(thread.id.to_s)
      group = Fabricate(:group)
      group.add(user)
      private_channel = Fabricate(:private_category_channel, group: group, threading_enabled: true)
      private_thread = Fabricate(:chat_thread, channel: private_channel)
      result = lookup(channel_id: private_channel.id, thread_id: private_thread.id)
      expect(result.dig("data", "chatThread", "id")).to eq(private_thread.id.to_s)
      GroupUser.where(group: group, user: user).delete_all
      result = lookup(channel_id: private_channel.id, thread_id: private_thread.id)
      expect(result.dig("data", "chatThread")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FORBIDDEN")
      expect(response.body).not_to include(private_thread.original_message.message)
    end

    it "retains channel binding, forced thread reads and deleted original moderation" do
      foreign_channel = Fabricate(:category_channel)
      result = lookup(channel_id: foreign_channel.id)
      expect(result.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
      channel.update!(threading_enabled: false)
      expect(lookup.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
      thread.update!(force: true)
      expect(lookup.dig("data", "chatThread", "force")).to eq(true)
      thread.original_message.trash!
      expect(lookup.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
      user.update!(moderator: true)
      expect(lookup.dig("data", "chatThread", "originalMessage", "deletedAt")).to be_present
    end

    it "creates a native thread and preserves existing thread repeat events and title" do
      original = Fabricate(:chat_message, chat_channel: channel, user: user)
      events = DiscourseEvent.track_events { create_thread(original: original, title: "A thread") }
      result = response.parsed_body
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "createChatThread", "success")).to eq(true)
      created = Chat::Thread.find(original.reload.thread_id)
      expect(created.title).to eq("A thread")
      expect(result.dig("data", "createChatThread", "thread")).to include("id" => created.id.to_s, "preview" => nil, "currentUserMembership" => nil)
      expect(events.map { |event| event[:event_name] }).to include(:chat_thread_created)
      count = Chat::Thread.count
      events = DiscourseEvent.track_events { create_thread(original: original, title: "Different") }
      expect(response.parsed_body.dig("data", "createChatThread", "thread", "id")).to eq(created.id.to_s)
      expect(Chat::Thread.count).to eq(count)
      expect(created.reload.title).to eq("A thread")
      expect(events.map { |event| event[:event_name] }).to include(:chat_thread_created)
    end

    it "retains create title, threading, silence and original channel validation" do
      original = Fabricate(:chat_message, chat_channel: channel, user: user)
      result = create_thread(original: original, title: "x" * 101)
      expect(result.dig("data", "createChatThread", "errors", 0, "code")).to eq("BAD_USER_INPUT")
      foreign = Fabricate(:chat_message)
      expect(create_thread(original: foreign).dig("data", "createChatThread", "success")).to eq(false)
      channel.update!(threading_enabled: false)
      expect(create_thread(original: original).dig("data", "createChatThread", "errors", 0, "code")).to eq("NOT_FOUND")
      channel.update!(threading_enabled: true)
      expect(UserSilencer.new(user).silence).to eq(true)
      expect(create_thread(original: original).dig("data", "createChatThread", "errors", 0, "code")).to eq("FORBIDDEN")
      expect(original.reload.thread_id).to be_nil
    end

    it "retains native private creation publication audience on repeat acknowledgment" do
      group = Fabricate(:group)
      group.add(user)
      private_channel = Fabricate(:private_category_channel, group: group, threading_enabled: true)
      original = Fabricate(:chat_message, chat_channel: private_channel, user: user)
      native_publications = MessageBus.track_publish do
        post "/chat/api/channels/#{private_channel.id}/threads.json", params: { original_message_id: original.id }, headers: headers
      end
      expect(response.status).to eq(200)
      publications = MessageBus.track_publish { create_thread(original: original, channel_id: private_channel.id) }
      expect(response.parsed_body.dig("data", "createChatThread", "success")).to eq(true)
      native = native_publications.select { |entry| entry.channel.start_with?("/chat/") }
      actual = publications.select { |entry| entry.channel.start_with?("/chat/") }
      expect(actual).to be_present
      expect(actual.map { |entry| [entry.channel, entry.user_ids, entry.group_ids] }).to eq(native.map { |entry| [entry.channel, entry.user_ids, entry.group_ids] })
      GroupUser.where(group: group, user: user).delete_all
      result = create_thread(original: original, channel_id: private_channel.id)
      expect(result.dig("data", "createChatThread", "errors", 0, "code")).to eq("FORBIDDEN")
    end

    it "preserves native sample ordering and counts beyond ten participants" do
      actors = Fabricate.times(12, :user)
      actors.each do |actor|
        thread.add(actor)
        message = Fabricate(:chat_message, chat_channel: channel, thread: thread, user: actor)
        thread.update!(last_message: message)
      end
      get "/chat/api/channels/#{channel.id}/threads/#{thread.id}.json", headers: headers
      expect(response.status).to eq(200)
      native = response.parsed_body.dig("thread", "preview")
      result = lookup(selection: "preview { participantCount participantUsers { id username } }")
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatThread", "preview", "participantCount")).to eq(native.fetch("participant_count").to_s)
      expected = native.fetch("participant_users").map { |actor| { "id" => actor.fetch("id").to_s, "username" => actor.fetch("username") } }
      expect(expected.size).to eq(10)
      expect(result.dig("data", "chatThread", "preview", "participantUsers")).to eq(expected)
    end

    it "keeps disabled lookup and creation roots nullable with siblings" do
      SiteSetting.chat_enabled = false
      result = lookup
      expect(result.dig("data", "chatThread")).to be_nil
      expect(result.dig("data", "__typename")).to eq("Query")
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FEATURE_DISABLED")
      result = create_thread(original: thread.original_message)
      expect(result.dig("data", "createChatThread")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FEATURE_DISABLED")
    end

    it "rejects excessive creation aliases before association changes" do
      original = Fabricate(:chat_message, chat_channel: channel, user: user)
      operations = 11.times.map { |index| "thread#{index}: createChatThread(input: { channelId: \"#{channel.id}\", originalMessageId: \"#{original.id}\" }) { success }" }.join(" ")
      result = graphql(query: "mutation { #{operations} }")
      expect(result.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
      expect(original.reload.thread_id).to be_nil
    end

    it "retains creation authentication, browser CSRF and global write guards" do
      original = Fabricate(:chat_message, chat_channel: channel, user: user)
      query = "mutation { createChatThread(input: { channelId: \"#{channel.id}\", originalMessageId: \"#{original.id}\" }) { success errors { code } } }"
      result = graphql(query: query, request_headers: {})
      expect(result.dig("data", "createChatThread", "errors", 0, "code")).to eq("UNAUTHENTICATED")
      get "/discourse-graphql/graphql", params: { query: query }, headers: headers
      expect(response.status).to eq(400)
      Discourse.enable_readonly_mode
      begin
        graphql(query: query)
        expect(response.status).to eq(503)
      ensure
        Discourse.disable_readonly_mode
      end
      SiteSetting.site_archived = true
      begin
        graphql(query: query)
        expect(response.status).to eq(503)
      ensure
        SiteSetting.site_archived = false
      end
      api_key.update!(scope_mode: :read_only, api_key_scopes: [ApiKeyScope.new(resource: "global", action: "read")])
      graphql(query: query)
      expect(response.status).to eq(403)
      sign_in(user)
      get "/session/csrf.json"
      token = response.parsed_body.fetch("csrf")
      previous = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      begin
        graphql(query: query, request_headers: {})
        expect(response.status).to eq(403)
        result = graphql(query: query, request_headers: { "X-CSRF-Token" => token, "X-Requested-With" => "XMLHttpRequest" })
        expect(result.dig("data", "createChatThread", "success")).to eq(true)
      ensure
        ActionController::Base.allow_forgery_protection = previous
      end
      expect(original.reload.thread_id).to be_present
    end
  end

  private

  def lookup(channel_id: channel.id, thread_id: thread.id, selection: nil, request_headers: headers)
    selection ||= "id title status channelId replyCount lastMessageId force originalMessage { id raw cooked channelId deletedAt author { id username } } preview { lastReplyId lastReplyExcerpt participantCount } currentUserMembership { threadId notificationLevel lastReadMessageId threadTitlePromptSeen } meta { messageBusLastIds { threadMessageBusLastId } }"
    graphql(query: "{ chatThread(channelId: \"#{channel_id}\", threadId: \"#{thread_id}\") { #{selection} } __typename }", request_headers: request_headers)
  end

  def create_thread(original:, title: nil, channel_id: channel.id)
    graphql(query: "mutation { createChatThread(input: { channelId: \"#{channel_id}\", originalMessageId: \"#{original.id}\", title: #{title.to_json} }) { success thread { id title preview { lastReplyId } currentUserMembership { threadId } originalMessage { id } } errors { code } } }")
  end

  def graphql(query:, request_headers: headers)
    post "/discourse-graphql/graphql", params: { query: query }, headers: request_headers, as: :json
    response.parsed_body
  end
end
