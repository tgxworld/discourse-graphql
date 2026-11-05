require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:other_user, :user)
  fab!(:channel) { Fabricate(:category_channel, threading_enabled: true) }
  fab!(:thread) { Fabricate(:chat_thread, channel: channel, original_message_user: user) }
  fab!(:reply) { Fabricate(:chat_message, chat_channel: channel, thread: thread) }

  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    SiteSetting.direct_message_enabled_groups = Group::AUTO_GROUPS[:everyone]
    channel.add(user)
    thread.update!(last_message: reply)
  end

  describe "#execute" do
    it "updates an authored title with native private metadata publication" do
      group = Fabricate(:group)
      group.add(user)
      private_channel = Fabricate(:private_category_channel, group: group, threading_enabled: true)
      private_thread = Fabricate(:chat_thread, channel: private_channel, original_message_user: user)
      native_publications = MessageBus.track_publish do
        put "/chat/api/channels/#{private_channel.id}/threads/#{private_thread.id}.json", params: { title: "Native title" }, headers: headers
      end
      expect(response.status).to eq(200)
      expect(private_thread.reload.title).to eq("Native title")
      publications = MessageBus.track_publish { action("updateChatThreadTitle(threadId: \"#{private_thread.id}\", title: \"GraphQL title\")") }
      expect(response.parsed_body.dig("data", "updateChatThreadTitle", "success")).to eq(true)
      expect(private_thread.reload.title).to eq("GraphQL title")
      native_messages = native_publications.select { |entry| entry.channel.start_with?("/chat/") }
      messages = publications.select { |entry| entry.channel.start_with?("/chat/") }
      expect(messages.map { |entry| [entry.channel, entry.user_ids, entry.group_ids] }).to eq(native_messages.map { |entry| [entry.channel, entry.user_ids, entry.group_ids] })
      expect(messages).to be_present
      expect(messages.map(&:data).to_json).to include(private_thread.title)
    end

    it "clears titles with null and omission and retains native length validation" do
      thread.update!(title: "Initial")
      result = action("updateChatThreadTitle(threadId: \"#{thread.id}\", title: null)")
      expect(result.dig("data", "updateChatThreadTitle", "success")).to eq(true)
      expect(thread.reload.title).to be_nil
      thread.update!(title: "Again")
      result = action("updateChatThreadTitle(threadId: \"#{thread.id}\")")
      expect(result.dig("data", "updateChatThreadTitle", "success")).to eq(true)
      expect(thread.reload.title).to be_nil
      result = action("updateChatThreadTitle(threadId: \"#{thread.id}\", title: #{("x" * 101).to_json})")
      expect(result.dig("data", "updateChatThreadTitle", "errors", 0, "code")).to eq("BAD_USER_INPUT")
      expect(thread.reload.title).to be_nil
    end

    it "retains title ownership, staff editing and silence restrictions" do
      other_thread = Fabricate(:chat_thread, channel: channel, original_message_user: other_user)
      result = action("updateChatThreadTitle(threadId: \"#{other_thread.id}\", title: \"Denied\")")
      expect(result.dig("data", "updateChatThreadTitle", "errors", 0, "code")).to eq("FORBIDDEN")
      user.update!(moderator: true)
      result = action("updateChatThreadTitle(threadId: \"#{other_thread.id}\", title: \"Staff title\")")
      expect(result.dig("data", "updateChatThreadTitle", "success")).to eq(true)
      expect(other_thread.reload.title).to eq("Staff title")
      UserSilencer.new(user).silence
      result = action("updateChatThreadTitle(threadId: \"#{thread.id}\", title: \"Silenced\")")
      expect(result.dig("data", "updateChatThreadTitle", "errors", 0, "code")).to eq("FORBIDDEN")
      expect(thread.reload.title).to be_nil
    end

    it "keeps native closed channel and disabled threading rules distinct" do
      channel.update!(status: :closed)
      expect(action("updateChatThreadTitle(threadId: \"#{thread.id}\", title: \"Closed title\")").dig("data", "updateChatThreadTitle", "success")).to eq(true)
      channel.update!(threading_enabled: false)
      expect(action("updateChatThreadTitle(threadId: \"#{thread.id}\", title: \"Denied\")").dig("data", "updateChatThreadTitle", "errors", 0, "code")).to eq("FORBIDDEN")
      result = action("markChatThreadRead(channelId: \"#{channel.id}\", threadId: \"#{thread.id}\")")
      expect(result.dig("data", "markChatThreadRead", "success")).to eq(true)
      expect(thread.membership_for(user).last_read_message_id).to eq(reply.id)
      result = membership("updateChatThreadNotifications(channelId: \"#{channel.id}\", threadId: \"#{thread.id}\", notificationLevel: NORMAL)")
      expect(result.dig("data", "updateChatThreadNotifications", "errors", 0, "code")).to eq("NOT_FOUND")
      result = membership("markChatThreadTitlePromptSeen(channelId: \"#{channel.id}\", threadId: \"#{thread.id}\")")
      expect(result.dig("data", "markChatThreadTitlePromptSeen", "errors", 0, "code")).to eq("NOT_FOUND")
    end

    it "creates notification membership with native last read initialization and enum zero" do
      thread.remove(user)
      native_thread = Fabricate(:chat_thread, channel: channel, original_message_user: other_user)
      put "/chat/api/channels/#{channel.id}/threads/#{native_thread.id}/notifications-settings/me.json", params: { notification_level: 0 }, headers: headers
      expect(response.status).to eq(200)
      native = response.parsed_body.fetch("membership")
      result = membership("updateChatThreadNotifications(channelId: \"#{channel.id}\", threadId: \"#{thread.id}\", notificationLevel: MUTED)")
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "updateChatThreadNotifications")).to eq("success" => true, "membership" => { "threadId" => thread.id.to_s, "lastReadMessageId" => reply.id.to_s, "notificationLevel" => "MUTED", "threadTitlePromptSeen" => native.fetch("thread_title_prompt_seen") }, "errors" => [])
      expect(thread.membership_for(user).notification_level).to eq("muted")
      expect(thread.membership_for(user).last_read_message_id).to eq(reply.id)
    end

    it "changes existing notifications while preserving read state and other actors" do
      actor_membership = thread.membership_for(user)
      actor_membership.update!(last_read_message_id: thread.original_message_id, thread_title_prompt_seen: true)
      other_membership = thread.add(other_user)
      %w[NORMAL TRACKING WATCHING MUTED].each do |level|
        result = membership("updateChatThreadNotifications(channelId: \"#{channel.id}\", threadId: \"#{thread.id}\", notificationLevel: #{level})")
        expect(result.dig("data", "updateChatThreadNotifications", "membership")).to eq("threadId" => thread.id.to_s, "lastReadMessageId" => thread.original_message_id.to_s, "notificationLevel" => level, "threadTitlePromptSeen" => true)
      end
      expect(actor_membership.reload.last_read_message_id).to eq(thread.original_message_id)
      expect(other_membership.reload.notification_level).to eq("tracking")
      result = membership("updateChatThreadNotifications(channelId: \"#{channel.id}\", threadId: \"#{thread.id}\", notificationLevel: INVALID)")
      expect(result.dig("errors", 0, "extensions", "code")).to eq("GRAPHQL_VALIDATION_FAILED")
      expect(actor_membership.reload.notification_level).to eq("muted")
    end

    it "acknowledges the prompt with normal membership without marking messages read" do
      thread.remove(user)
      publications = MessageBus.track_publish("/chat/user-has-threads/#{user.id}") do
        membership("markChatThreadTitlePromptSeen(channelId: \"#{channel.id}\", threadId: \"#{thread.id}\")")
      end
      result = response.parsed_body
      expect(result.dig("data", "markChatThreadTitlePromptSeen", "membership")).to eq("threadId" => thread.id.to_s, "lastReadMessageId" => nil, "notificationLevel" => "NORMAL", "threadTitlePromptSeen" => true)
      expect(publications).to include(have_attributes(user_ids: [user.id], data: { "has_threads" => true }))
      actor_membership = thread.membership_for(user)
      actor_membership.update!(notification_level: :watching, last_read_message_id: thread.original_message_id)
      expect { membership("markChatThreadTitlePromptSeen(channelId: \"#{channel.id}\", threadId: \"#{thread.id}\")") }.not_to change(Chat::UserChatThreadMembership, :count)
      expect(actor_membership.reload.attributes.slice("notification_level", "last_read_message_id", "thread_title_prompt_seen")).to eq("notification_level" => "watching", "last_read_message_id" => thread.original_message_id, "thread_title_prompt_seen" => true)
    end

    it "preserves serializer omissions in selected membership output" do
      restricted = Class.new(Chat::BaseThreadMembershipSerializer) do
        def initialize(object, options = {})
          super(object, options.merge(only: [:thread_id]))
        end
      end
      stub_const(Chat, :BaseThreadMembershipSerializer, restricted) do
        result = membership("updateChatThreadNotifications(channelId: \"#{channel.id}\", threadId: \"#{thread.id}\", notificationLevel: NORMAL)")
        expect(result.dig("data", "updateChatThreadNotifications", "membership")).to eq("threadId" => thread.id.to_s, "lastReadMessageId" => nil, "notificationLevel" => nil, "threadTitlePromptSeen" => nil)
      end
    end

    it "marks explicit and latest reading progress with native mention and tracking effects" do
      notification = Notification.create!(notification_type: Notification.types[:chat_mention], user: user, read: false, data: { message: "chat.mention_notification", chat_message_id: reply.id, chat_channel_id: channel.id, mentioned_by_username: reply.user.username }.to_json)
      Chat::UserMention.create!(user: user, chat_message: reply, notifications: [notification])
      publications = MessageBus.track_publish("/chat/user-tracking-state/#{user.id}") do
        action("markChatThreadRead(channelId: \"#{channel.id}\", threadId: \"#{thread.id}\", messageId: \"#{reply.id}\")")
      end
      expect(response.parsed_body.dig("data", "markChatThreadRead", "success")).to eq(true)
      expect(thread.membership_for(user).last_read_message_id).to eq(reply.id)
      expect(notification.reload.read).to eq(true)
      expect(publications).to include(have_attributes(user_ids: [user.id], data: include("thread_id" => thread.id, "last_read_message_id" => reply.id)))
      newer = Fabricate(:chat_message, chat_channel: channel, thread: thread)
      thread.update!(last_message: newer)
      result = action("markChatThreadRead(channelId: \"#{channel.id}\", threadId: \"#{thread.id}\", messageId: null)")
      expect(result.dig("data", "markChatThreadRead", "success")).to eq(true)
      expect(thread.membership_for(user).last_read_message_id).to eq(newer.id)
      newest = Fabricate(:chat_message, chat_channel: channel, thread: thread)
      newest.trash!
      thread.update!(last_message_id: newest.id)
      result = action("markChatThreadRead(channelId: \"#{channel.id}\", threadId: \"#{thread.id}\")")
      expect(result.dig("data", "markChatThreadRead", "success")).to eq(true)
      expect(thread.membership_for(user).last_read_message_id).to eq(newest.id)
    end

    it "retains missing membership and backward reading failures without new membership" do
      actor_membership = thread.membership_for(user)
      actor_membership.update!(last_read_message_id: reply.id)
      result = action("markChatThreadRead(channelId: \"#{channel.id}\", threadId: \"#{thread.id}\", messageId: \"#{thread.original_message_id}\")")
      expect(result.dig("data", "markChatThreadRead", "errors", 0, "code")).to eq("BAD_USER_INPUT")
      expect(actor_membership.reload.last_read_message_id).to eq(reply.id)
      thread.remove(user)
      result = action("markChatThreadRead(channelId: \"#{channel.id}\", threadId: \"#{thread.id}\")")
      expect(result.dig("data", "markChatThreadRead", "errors", 0, "code")).to eq("BAD_USER_INPUT")
      expect(thread.membership_for(user)).to be_nil
    end

    it "retains channel and message binding for reading and preference changes" do
      foreign_channel = Fabricate(:category_channel, threading_enabled: true)
      foreign_message = Fabricate(:chat_message, chat_channel: channel)
      operations = [
        "markChatThreadRead(channelId: \"#{foreign_channel.id}\", threadId: \"#{thread.id}\")",
        "markChatThreadRead(channelId: \"#{channel.id}\", threadId: \"#{thread.id}\", messageId: \"#{foreign_message.id}\")",
        "updateChatThreadNotifications(channelId: \"#{foreign_channel.id}\", threadId: \"#{thread.id}\", notificationLevel: NORMAL)",
        "markChatThreadTitlePromptSeen(channelId: \"#{foreign_channel.id}\", threadId: \"#{thread.id}\")",
      ]
      operations.each do |operation|
        result = action(operation)
        expect(result.fetch("data").values.first.dig("errors", 0, "code")).to eq("NOT_FOUND")
      end
      expect(thread.membership_for(user).last_read_message_id).to be_nil
    end

    it "rechecks private owning channel access after revocation for every control" do
      group = Fabricate(:group)
      group.add(user)
      private_channel = Fabricate(:private_category_channel, group: group, threading_enabled: true)
      private_thread = Fabricate(:chat_thread, channel: private_channel, original_message_user: user)
      GroupUser.where(group: group, user: user).delete_all
      operations = [
        "updateChatThreadTitle(threadId: \"#{private_thread.id}\", title: \"Denied\")",
        "markChatThreadRead(channelId: \"#{private_channel.id}\", threadId: \"#{private_thread.id}\")",
        "updateChatThreadNotifications(channelId: \"#{private_channel.id}\", threadId: \"#{private_thread.id}\", notificationLevel: NORMAL)",
        "markChatThreadTitlePromptSeen(channelId: \"#{private_channel.id}\", threadId: \"#{private_thread.id}\")",
      ]
      publications = MessageBus.track_publish do
        operations.each do |operation|
          result = action(operation)
          expect(result.fetch("data").values.first.fetch("success")).to eq(false)
          expect(result.fetch("data").values.first.dig("errors", 0, "code")).to eq("FORBIDDEN")
        end
      end
      expect(private_thread.reload.title).to be_nil
      expect(private_thread.membership_for(user).thread_title_prompt_seen).to eq(false)
      expect(publications.select { |entry| entry.channel.start_with?("/chat/") }).to be_empty
    end

    it "rejects excessive combined changes before the first write" do
      operations = 11.times.map { |index| "title#{index}: updateChatThreadTitle(threadId: \"#{thread.id}\", title: \"Title #{index}\") { success }" }.join(" ")
      result = graphql(query: "mutation { #{operations} }")
      expect(result.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
      expect(thread.reload.title).to be_nil
    end

    it "keeps native authentication, GET rejection and disabled sibling results" do
      operation = "markChatThreadRead(channelId: \"#{channel.id}\", threadId: \"#{thread.id}\")"
      result = graphql(query: "mutation { #{operation} { success errors { code } } }", request_headers: {})
      expect(result.dig("data", "markChatThreadRead", "errors", 0, "code")).to eq("UNAUTHENTICATED")
      get "/discourse-graphql/graphql", params: { query: "mutation { #{operation} { success } }" }, headers: headers
      expect(response.status).to eq(400)
      SiteSetting.chat_enabled = false
      result = graphql(query: "mutation { #{operation} { success } __typename }")
      expect(result.dig("data", "markChatThreadRead")).to be_nil
      expect(result.dig("data", "__typename")).to eq("Mutation")
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FEATURE_DISABLED")
    end

    it "retains readonly, archived and read credential restrictions before native effects" do
      query = "mutation { updateChatThreadTitle(threadId: \"#{thread.id}\", title: \"Denied\") { success } }"
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
      expect(thread.reload.title).to be_nil
    end

    it "requires browser CSRF and permits a native session token" do
      sign_in(user)
      get "/session/csrf.json"
      token = response.parsed_body.fetch("csrf")
      query = "mutation { updateChatThreadTitle(threadId: \"#{thread.id}\", title: \"Session title\") { success errors { code } } }"
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      begin
        graphql(query: query, request_headers: {})
        expect(response.status).to eq(403)
        expect(thread.reload.title).to be_nil
        result = graphql(query: query, request_headers: { "X-CSRF-Token" => token, "X-Requested-With" => "XMLHttpRequest" })
        expect(result.dig("data", "updateChatThreadTitle", "success")).to eq(true)
        expect(thread.reload.title).to eq("Session title")
      ensure
        ActionController::Base.allow_forgery_protection = original
      end
    end
  end

  private

  def action(operation)
    graphql(query: "mutation { #{operation} { success errors { code } } }")
  end

  def membership(operation)
    graphql(query: "mutation { #{operation} { success membership { threadId lastReadMessageId notificationLevel threadTitlePromptSeen } errors { code } } }")
  end

  def graphql(query:, request_headers: headers)
    post "/discourse-graphql/graphql", params: { query: query }, headers: request_headers, as: :json
    response.parsed_body
  end
end
