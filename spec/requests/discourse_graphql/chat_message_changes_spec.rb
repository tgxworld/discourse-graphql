require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:channel, :category_channel)
  fab!(:message) do
    Fabricate(:chat_message, chat_channel: channel, user: user, created_at: 1.hour.ago)
  end

  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    channel.add(user)
  end

  describe "#execute" do
    it "edits native text with cooking, revisions and private publications" do
      group = Fabricate(:group, users: [user])
      channel.chatable.set_permissions(group => :full)
      channel.chatable.save!
      native_publications =
        MessageBus.track_publish do
          put "/chat/api/channels/#{channel.id}/messages/#{message.id}.json",
              params: {
                message: "Native publication baseline",
              },
              headers: headers,
              as: :json
        end
      expect(response.status).to eq(200)
      original = message.reload.message
      events = nil
      publications =
        MessageBus.track_publish do
          events =
            DiscourseEvent.track_events do
              expect(
                edit(input: { message: "  **Edited content**  " }).dig("data", "updateChatMessage"),
              ).to eq("success" => true, "errors" => [])
            end
        end
      expect(message.reload.message).to eq("**Edited content**")
      expect(message.cooked).to include("<strong>Edited content</strong>")
      revision = message.revisions.last
      expect(revision).to have_attributes(
        old_message: original,
        new_message: message.message,
        user_id: user.id,
      )
      expect(events).to include(include(event_name: :chat_message_edited))
      expect(publications).to include(have_attributes(channel: "/chat/#{channel.id}"))
      expect(
        publications.select { |entry| entry.channel == "/chat/#{channel.id}" }.map(&:group_ids),
      ).to eq(
        native_publications
          .select { |entry| entry.channel == "/chat/#{channel.id}" }
          .map(&:group_ids),
      )
      get "/chat/api/channels/#{channel.id}/messages.json",
          params: {
            page_size: 1,
          },
          headers: headers
      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("messages", 0, "cooked")).to eq(message.cooked)
    end

    it "creates and edits attachment only messages using an explicit empty String" do
      upload = Fabricate(:upload, user: user)
      post "/discourse-graphql/graphql",
           params: {
             query:
               "mutation($input: CreateChatMessageInput!) { createChatMessage(input: $input) { status messageId errors { code } } }",
             variables: {
               input: {
                 channelId: channel.id.to_s,
                 message: "",
                 uploadIds: [upload.id.to_s],
               },
             },
           },
           headers: headers,
           as: :json
      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("data", "createChatMessage", "status")).to eq("CREATED")
      created =
        Chat::Message.find(response.parsed_body.dig("data", "createChatMessage", "messageId"))
      expect(created.upload_ids).to eq([upload.id])

      result = edit(input: { message: "", uploadIds: [upload.id.to_s] })

      expect(result.dig("data", "updateChatMessage", "success")).to eq(true)
      expect(message.reload.message).to eq("")
      expect(message.upload_ids).to eq([upload.id])
    end

    it "retains native upload replacement for omitted, null and empty lists" do
      owned = Fabricate(:upload, user: user)
      [{}, { uploadIds: nil }, { uploadIds: [] }].each_with_index do |patch, index|
        message.uploads = [owned]
        result = edit(input: patch.merge(message: "Replacement #{index}"))
        expect(result.dig("data", "updateChatMessage", "success")).to eq(true)
        expect(message.reload.upload_ids).to eq([])
      end
      result = edit(input: { message: "Retained attachment", uploadIds: [owned.id.to_s] })
      expect(result.dig("data", "updateChatMessage", "success")).to eq(true)
      expect(message.reload.upload_ids).to eq([owned.id])
    end

    it "preserves native attachment retention after foreign, mixed and duplicate ID mismatches" do
      original = Fabricate(:upload, user: user)
      owned = Fabricate(:upload, user: user)
      foreign = Fabricate(:upload)
      message.uploads = [original]
      [[foreign.id], [owned.id, foreign.id], [owned.id, owned.id]].each_with_index do |ids, index|
        result = edit(input: { message: "Native mismatch #{index}", uploadIds: ids.map(&:to_s) })
        expect(result.dig("data", "updateChatMessage", "success")).to eq(true)
        expect(message.reload.message).to eq("Native mismatch #{index}")
        expect(message.upload_ids).to eq([original.id])
      end
    end

    it "retains native creation filtering without attaching another actor's upload" do
      owned = Fabricate(:upload, user: user)
      foreign = Fabricate(:upload)
      post "/discourse-graphql/graphql",
           params: {
             query:
               "mutation($input: CreateChatMessageInput!) { createChatMessage(input: $input) { status messageId } }",
             variables: {
               input: {
                 channelId: channel.id.to_s,
                 message: "Mixed creation",
                 uploadIds: [owned.id.to_s, foreign.id.to_s],
               },
             },
           },
           headers: headers,
           as: :json
      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("data", "createChatMessage", "status")).to eq("CREATED")
      expect(
        Chat::Message.find(
          response.parsed_body.dig("data", "createChatMessage", "messageId"),
        ).upload_ids,
      ).to eq([owned.id])
    end

    it "contains native null text edit failure without changing persisted state" do
      owned = Fabricate(:upload, user: user)
      original = message.message
      [{}, { message: nil }].each do |input|
        result = edit(input: input.merge(uploadIds: [owned.id.to_s]))
        expect(result.dig("data", "updateChatMessage")).to be_nil
        expect(result.dig("data", "__typename")).to eq("Mutation")
        expect(result.dig("errors", 0, "extensions", "code")).to eq("INTERNAL_ERROR")
        expect(result.to_s).not_to include("NoMethodError", "message.length")
        expect(message.reload.message).to eq(original)
        expect(message.upload_ids).to eq([])
      end
    end

    it "retains native rejection of omitted and null creation text with uploads" do
      owned = Fabricate(:upload, user: user)
      [{}, { message: nil }].each do |input|
        expect do
          post "/discourse-graphql/graphql",
               params: {
                 query:
                   "mutation($input: CreateChatMessageInput!) { createChatMessage(input: $input) { status errors { code } } }",
                 variables: {
                   input: input.merge(channelId: channel.id.to_s, uploadIds: [owned.id.to_s]),
                 },
               },
               headers: headers,
               as: :json
        end.not_to change(Chat::Message, :count)
        expect(response.status).to eq(200)
        expect(response.parsed_body.dig("data", "createChatMessage", "status")).to eq("FAILED")
      end
    end

    it "retains native empty and overlength edit validation" do
      original = message.message
      ["", "x" * (SiteSetting.chat_maximum_message_length + 1)].each do |text|
        result = edit(input: { message: text })
        expect(result.dig("data", "updateChatMessage", "success")).to eq(false)
        expect(result.dig("data", "updateChatMessage", "errors", 0, "code")).to eq("BAD_USER_INPUT")
        expect(message.reload.message).to eq(original)
      end
    end

    it "deletes with native pin, notification and channel reading cleanup" do
      SiteSetting.chat_pinned_messages = true
      earlier = Fabricate(:chat_message, chat_channel: channel, user: user, created_at: 2.hours.ago)
      channel.update!(last_message: message)
      membership = channel.membership_for(user)
      membership.update!(last_read_message: message)
      pin = Fabricate(:chat_pinned_message, chat_message: message, user: user)
      notification = Fabricate(:notification)
      Fabricate(:user_chat_mention, chat_message: message, notifications: [notification])
      events =
        DiscourseEvent.track_events do
          expect(
            message_action("deleteChatMessage").dig("data", "deleteChatMessage", "success"),
          ).to eq(true)
        end
      expect(message.reload).to be_trashed
      expect(message.deleted_by_id).to eq(user.id)
      expect(Chat::PinnedMessage.exists?(pin.id)).to eq(false)
      expect(Notification.exists?(notification.id)).to eq(false)
      expect(channel.reload.last_message_id).to eq(earlier.id)
      expect(membership.reload.last_read_message_id).to eq(earlier.id)
      expect(events).to include(include(event_name: :chat_message_trashed))
    end

    it "restores native content and publishes recovery without restoring a removed pin" do
      message_action("deleteChatMessage")
      expect(message.reload).to be_trashed
      publications = nil
      events =
        DiscourseEvent.track_events do
          publications =
            MessageBus.track_publish do
              expect(
                message_action("restoreChatMessage").dig("data", "restoreChatMessage", "success"),
              ).to eq(true)
            end
        end
      expect(message.reload.deleted_at).to be_nil
      expect(channel.reload.last_message_id).to eq(message.id)
      expect(events).to include(include(event_name: :chat_message_restored))
      expect(publications).to include(have_attributes(channel: "/chat/#{channel.id}"))
    end

    it "updates native thread reply counts, reading state and publications through delete and restore" do
      channel.update!(threading_enabled: true)
      thread = Fabricate(:chat_thread, channel: channel, original_message_user: user)
      earlier = Fabricate(:chat_message, chat_channel: channel, thread: thread, user: user)
      reply = Fabricate(:chat_message, chat_channel: channel, thread: thread, user: user)
      thread.update!(last_message: reply, replies_count: 2)
      membership = thread.add(user)
      membership.update!(last_read_message: reply)
      get "/chat/api/channels/#{channel.id}/threads/#{thread.id}.json", headers: headers
      expect(response.parsed_body.dig("thread", "reply_count")).to eq(2)

      publications =
        MessageBus.track_publish do
          expect(
            message_action("deleteChatMessage", message_id: reply.id).dig(
              "data",
              "deleteChatMessage",
              "success",
            ),
          ).to eq(true)
        end
      expect(reply.reload).to be_trashed
      expect(thread.reload.last_message_id).to eq(earlier.id)
      expect(membership.reload.last_read_message_id).to eq(earlier.id)
      get "/chat/api/channels/#{channel.id}/threads/#{thread.id}.json", headers: headers
      expect(response.parsed_body.dig("thread", "reply_count")).to eq(1)
      expect(publications).to include(
        have_attributes(channel: "/chat/#{channel.id}/thread/#{thread.id}"),
      )

      expect(
        message_action("restoreChatMessage", message_id: reply.id).dig(
          "data",
          "restoreChatMessage",
          "success",
        ),
      ).to eq(true)
      expect(thread.reload.last_message_id).to eq(reply.id)
      get "/chat/api/channels/#{channel.id}/threads/#{thread.id}.json", headers: headers
      expect(response.parsed_body.dig("thread", "reply_count")).to eq(2)
    end

    it "preserves serial edit, delete and restore effects within one request" do
      reference = "channelId: #{channel.id.to_s.to_json}, messageId: #{message.id.to_s.to_json}"
      result =
        graphql(
          query:
            "mutation { edit: updateChatMessage(input: { #{reference}, message: \"Serial content\" }) { success } remove: deleteChatMessage(#{reference}) { success } recover: restoreChatMessage(#{reference}) { success } }",
        )
      expect(result["errors"]).to be_blank
      expect(result.fetch("data").values).to eq([{ "success" => true }] * 3)
      expect(message.reload.message).to eq("Serial content")
      expect(message.deleted_at).to be_nil
    end

    it "retains native closed channel restrictions and administrator exception" do
      channel.closed!(Discourse.system_user)
      result = edit(input: { message: "Closed channel" })
      expect(result.dig("data", "updateChatMessage", "errors", 0, "code")).to eq("BAD_USER_INPUT")
      result = message_action("deleteChatMessage")
      expect(result.dig("data", "deleteChatMessage", "errors", 0, "code")).to eq("FORBIDDEN")
      expect(message.reload.deleted_at).to be_nil
      user.update!(admin: true)
      result = edit(input: { message: "Administrator closed edit" })
      expect(result.dig("data", "updateChatMessage", "success")).to eq(true)
      expect(message.reload.message).to eq("Administrator closed edit")
    end

    it "preserves native author, moderator and administrator edit differences" do
      other = Fabricate(:chat_message, chat_channel: channel)
      result = edit(input: { message: "Denied other author" }, message_id: other.id)
      expect(result.dig("data", "updateChatMessage", "errors", 0, "code")).to eq("FORBIDDEN")
      user.update!(moderator: true)
      result = edit(input: { message: "Denied moderator" }, message_id: other.id)
      expect(result.dig("data", "updateChatMessage", "errors", 0, "code")).to eq("FORBIDDEN")
      user.update!(admin: true)
      result = edit(input: { message: "Administrator edit" }, message_id: other.id)
      expect(result.dig("data", "updateChatMessage", "success")).to eq(true)
      expect(other.reload.message).to eq("Administrator edit")
    end

    it "preserves distinct native membership requirements" do
      channel.membership_for(user).destroy!
      result = edit(input: { message: "No membership" })
      expect(result.dig("data", "updateChatMessage", "errors", 0, "code")).to eq("NOT_FOUND")
      expect(message_action("deleteChatMessage").dig("data", "deleteChatMessage", "success")).to eq(
        true,
      )
      expect(
        message_action("restoreChatMessage").dig("data", "restoreChatMessage", "success"),
      ).to eq(true)
      expect(channel.membership_for(user)).to be_nil
    end

    it "rechecks private access before author edits, deletes and restores" do
      group = Fabricate(:group, users: [user])
      private_channel = Fabricate(:private_category_channel, group: group)
      private_channel.add(user)
      entry = Fabricate(:chat_message, chat_channel: private_channel, user: user)
      deleted = Fabricate(:chat_message, chat_channel: private_channel, user: user)
      deleted.trash!(user)
      GroupUser.where(group: group, user: user).destroy_all
      result =
        edit(input: { message: "Forbidden" }, channel_id: private_channel.id, message_id: entry.id)
      expect(result.dig("data", "updateChatMessage", "errors", 0, "code")).to eq("FORBIDDEN")
      %w[deleteChatMessage restoreChatMessage].each do |field|
        result =
          message_action(
            field,
            channel_id: private_channel.id,
            message_id: field == "restoreChatMessage" ? deleted.id : entry.id,
          )
        expect(result.dig("data", field, "errors", 0, "code")).to eq("FORBIDDEN")
      end
      expect(entry.reload.deleted_at).to be_nil
      expect(deleted.reload).to be_trashed
    end

    it "retains native channel and message binding" do
      wrong_channel = Fabricate(:category_channel)
      result = edit(input: { message: "Wrong channel" }, channel_id: wrong_channel.id)
      expect(result.dig("data", "updateChatMessage", "errors", 0, "code")).to eq("NOT_FOUND")
      %w[deleteChatMessage restoreChatMessage].each do |field|
        result = message_action(field, channel_id: wrong_channel.id)
        expect(result.dig("data", field, "errors", 0, "code")).to eq("NOT_FOUND")
      end
    end

    it "rejects a silenced actor restoring a self deleted direct message" do
      recipient = Fabricate(:user)
      direct = Fabricate(:direct_message_channel, users: [user, recipient])
      entry = Fabricate(:chat_message, chat_channel: direct, user: user)
      entry.trash!(user)
      UserSilencer.new(user).silence
      events =
        DiscourseEvent.track_events do
          result = message_action("restoreChatMessage", channel_id: direct.id, message_id: entry.id)
          expect(result.dig("data", "restoreChatMessage", "errors", 0, "code")).to eq("FORBIDDEN")
        end
      expect(entry.reload).to be_trashed
      expect(events).not_to include(include(event_name: :chat_message_restored))
    end

    it "denies a bulk selection containing another author's message before deleting any row" do
      other = Fabricate(:chat_message, chat_channel: channel)
      result = bulk(ids: [message.id, other.id])
      expect(result.dig("data", "deleteChatMessages", "errors", 0, "code")).to eq("FORBIDDEN")
      expect(message.reload.deleted_at).to be_nil
      expect(other.reload.deleted_at).to be_nil
    end

    it "preserves native bulk filtering and missing selection errors" do
      foreign = Fabricate(:chat_message)
      result = bulk(ids: [message.id, foreign.id])
      expect(result.dig("data", "deleteChatMessages")).to eq("success" => true, "errors" => [])
      expect(message.reload).to be_trashed
      expect(foreign.reload.deleted_at).to be_nil
      result = bulk(ids: [foreign.id])
      expect(result.dig("data", "deleteChatMessages", "errors", 0, "code")).to eq("NOT_FOUND")
    end

    it "accepts the complete native two hundred message bulk window" do
      entries = Fabricate.times(200, :chat_message, chat_channel: channel, user: user)
      result = bulk(ids: entries.map(&:id))
      expect(result.dig("data", "deleteChatMessages", "success")).to eq(true)
      expect(Chat::Message.where(id: entries.map(&:id)).count).to eq(0)
      expect(
        Chat::Message.with_deleted.where(id: entries.map(&:id)).where.not(deleted_at: nil).count,
      ).to eq(200)
    end

    it "bounds upload IDs and bulk IDs before native work" do
      result = edit(input: { message: "Too many uploads", uploadIds: Array.new(201, "0") })
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      [[], Array.new(201, message.id)].each do |ids|
        result = bulk(ids: ids)
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
        expect(message.reload.deleted_at).to be_nil
      end
    end

    it "rejects multiplied destructive work before deleting messages" do
      selections =
        11
          .times
          .map do |index|
            "a#{index}: deleteChatMessage(channelId: #{channel.id.to_s.to_json}, messageId: #{message.id.to_s.to_json}) { success }"
          end
          .join(" ")
      result = graphql(query: "mutation { #{selections} }")
      expect(result.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
      expect(message.reload.deleted_at).to be_nil
    end

    it "retains anonymous denial and disabled sibling execution" do
      %w[deleteChatMessage restoreChatMessage].each do |field|
        result = message_action(field, request_headers: {})
        expect(result.dig("data", field, "errors", 0, "code")).to eq("UNAUTHENTICATED")
      end
      SiteSetting.chat_enabled = false
      result = edit(input: { message: "Disabled" })
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FEATURE_DISABLED")
      expect(result.dig("data", "__typename")).to eq("Mutation")
      expect(message.reload.deleted_at).to be_nil
    end

    it "retains GET, readonly and read credential protections" do
      query =
        "mutation { deleteChatMessage(channelId: #{channel.id.to_s.to_json}, messageId: #{message.id.to_s.to_json}) { success } }"
      get "/discourse-graphql/graphql", params: { query: query }, headers: headers
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_REQUEST")
      Discourse.enable_readonly_mode
      begin
        graphql(query: query, expected_status: 503)
        expect(response.status).to eq(503)
      ensure
        Discourse.disable_readonly_mode
      end
      api_key.update!(
        scope_mode: :read_only,
        api_key_scopes: [ApiKeyScope.new(resource: "global", action: "read")],
      )
      graphql(query: query, expected_status: 403)
      expect(response.status).to eq(403)
      expect(message.reload.deleted_at).to be_nil
    end

    it "requires browser CSRF before allowing an edit" do
      sign_in(user)
      get "/session/csrf.json"
      token = response.parsed_body.fetch("csrf")
      previous = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      begin
        edit(input: { message: "Denied browser edit" }, request_headers: {}, expected_status: 403)
        result =
          edit(
            input: {
              message: "Browser edit",
            },
            request_headers: {
              "X-CSRF-Token" => token,
              "X-Requested-With" => "XMLHttpRequest",
            },
          )
        expect(result.dig("data", "updateChatMessage", "success")).to eq(true)
        expect(message.reload.message).to eq("Browser edit")
      ensure
        ActionController::Base.allow_forgery_protection = previous
      end
    end
  end

  private

  def edit(
    input:,
    channel_id: channel.id,
    message_id: message.id,
    request_headers: headers,
    expected_status: 200
  )
    graphql(
      query:
        "mutation($input: UpdateChatMessageInput!) { updateChatMessage(input: $input) { success errors { code } } __typename }",
      variables: {
        input: { channelId: channel_id.to_s, messageId: message_id.to_s }.merge(input),
      },
      request_headers: request_headers,
      expected_status: expected_status,
    )
  end

  def message_action(
    field,
    channel_id: channel.id,
    message_id: message.id,
    request_headers: headers
  )
    graphql(
      query:
        "mutation { #{field}(channelId: #{channel_id.to_s.to_json}, messageId: #{message_id.to_s.to_json}) { success errors { code } } __typename }",
      request_headers: request_headers,
    )
  end

  def bulk(ids:)
    graphql(
      query:
        "mutation($ids: [ID!]!) { deleteChatMessages(channelId: #{channel.id.to_s.to_json}, messageIds: $ids) { success errors { code } } __typename }",
      variables: {
        ids: ids.map(&:to_s),
      },
    )
  end

  def graphql(query:, variables: {}, request_headers: headers, expected_status: 200)
    post "/discourse-graphql/graphql",
         params: {
           query: query,
           variables: variables,
         },
         headers: request_headers,
         as: :json
    expect(response.status).to eq(expected_status)
    response.parsed_body
  end
end
