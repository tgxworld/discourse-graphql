require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:pinning_group) { Fabricate(:group, users: [user]) }
  fab!(:channel, :category_channel)
  fab!(:message) { Fabricate(:chat_message, chat_channel: channel) }

  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_pinned_messages = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    SiteSetting.chat_pinning_messages_allowed_groups = pinning_group.id
    channel.add(user)
  end

  describe "#execute" do
    it "pins and unpins with native private publication payloads and audiences" do
      channel.chatable.set_permissions(pinning_group => :full)
      channel.chatable.save!
      freeze_time
      native_pin = MessageBus.track_publish do
        post "/chat/api/channels/#{channel.id}/messages/#{message.id}/pin.json", headers: headers
      end
      expect(response.status).to eq(200)
      delete "/chat/api/channels/#{channel.id}/messages/#{message.id}/pin.json", headers: headers
      expect(response.status).to eq(200)

      actual_pin = MessageBus.track_publish do
        expect(pin_action("pinChatMessage").dig("data", "pinChatMessage")).to eq("success" => true, "errors" => [])
      end
      pin = Chat::PinnedMessage.find_by!(chat_message: message)
      expect(pin.pinned_by_id).to eq(user.id)
      expect(actual_pin.map { |entry| [entry.channel, entry.user_ids, entry.group_ids, entry.data] }).to eq(native_pin.map { |entry| [entry.channel, entry.user_ids, entry.group_ids, entry.data] })
      native_unpin = MessageBus.track_publish do
        delete "/chat/api/channels/#{channel.id}/messages/#{message.id}/pin.json", headers: headers
      end
      expect(response.status).to eq(200)
      pin_action("pinChatMessage")
      actual_unpin = MessageBus.track_publish do
        expect(pin_action("unpinChatMessage").dig("data", "unpinChatMessage", "success")).to eq(true)
      end
      expect(Chat::PinnedMessage.where(chat_message: message)).not_to exist
      expect(actual_unpin.map { |entry| [entry.channel, entry.user_ids, entry.group_ids, entry.data] }).to eq(native_unpin.map { |entry| [entry.channel, entry.user_ids, entry.group_ids, entry.data] })
    end

    it "preserves native singular duplicate and missing pin messages" do
      pin = Fabricate(:chat_pinned_message, chat_message: message, user: user)
      post "/chat/api/channels/#{channel.id}/messages/#{message.id}/pin.json", headers: headers
      expect(response.status).to eq(422)
      duplicate_error = response.parsed_body.fetch("error")

      result = pin_action("pinChatMessage")

      expect(result.dig("data", "pinChatMessage")).to eq("success" => false, "errors" => [{ "code" => "BAD_USER_INPUT", "message" => duplicate_error }])
      pin.destroy!
      delete "/chat/api/channels/#{channel.id}/messages/#{message.id}/pin.json", headers: headers
      expect(response.status).to eq(422)
      missing_error = response.parsed_body.fetch("error")
      result = pin_action("unpinChatMessage")
      expect(result.dig("data", "unpinChatMessage")).to eq("success" => false, "errors" => [{ "code" => "BAD_USER_INPUT", "message" => missing_error }])
    end

    it "retains the native twenty pin limit and its error message" do
      20.times do
        entry = Fabricate(:chat_message, chat_channel: channel)
        Fabricate(:chat_pinned_message, chat_message: entry)
      end
      post "/chat/api/channels/#{channel.id}/messages/#{message.id}/pin.json", headers: headers
      expect(response.status).to eq(422)
      native_error = response.parsed_body.fetch("error")
      result = pin_action("pinChatMessage")
      expect(result.dig("data", "pinChatMessage", "errors")).to eq([{ "code" => "BAD_USER_INPUT", "message" => native_error }])
      expect(Chat::PinnedMessage.where(chat_channel: channel).count).to eq(20)
      expect(Chat::PinnedMessage.where(chat_message: message)).not_to exist
    end

    it "uses native category pinning groups while retaining direct message participant rights" do
      pinning_group.remove(user)
      result = pin_action("pinChatMessage")
      expect(result.dig("data", "pinChatMessage", "errors", 0, "code")).to eq("FORBIDDEN")
      direct = Fabricate(:direct_message_channel, users: [user, Fabricate(:user)])
      direct_message = Fabricate(:chat_message, chat_channel: direct)
      result = pin_action("pinChatMessage", channel_id: direct.id, message_id: direct_message.id)
      expect(result.dig("data", "pinChatMessage", "success")).to eq(true)
      expect(pin_action("unpinChatMessage", channel_id: direct.id, message_id: direct_message.id).dig("data", "unpinChatMessage", "success")).to eq(true)
    end

    it "rechecks private access before changing pins or the reading timestamp" do
      channel.chatable.set_permissions(pinning_group => :full)
      channel.chatable.save!
      Fabricate(:chat_pinned_message, chat_message: message, user: user)
      pinning_group.remove(user)
      %w[pinChatMessage unpinChatMessage markChatPinsRead].each do |field|
        result = pin_action(field)
        expect(result.dig("data", field, "errors", 0, "code")).to eq("FORBIDDEN")
      end
      expect(Chat::PinnedMessage.where(chat_message: message)).to exist
      expect(channel.membership_for(user).last_viewed_pins_at).to be_nil
    end

    it "retains native message and channel identity binding" do
      foreign_channel = Fabricate(:category_channel)
      %w[pinChatMessage unpinChatMessage].each do |field|
        result = pin_action(field, channel_id: foreign_channel.id)
        expect(result.dig("data", field, "errors", 0, "code")).to eq("NOT_FOUND")
      end
      result = pin_action("markChatPinsRead", channel_id: "0")
      expect(result.dig("data", "markChatPinsRead", "errors", 0, "code")).to eq("NOT_FOUND")
      expect(Chat::PinnedMessage.where(chat_message: message)).not_to exist
    end

    it "preserves the distinct native membership requirement for read acknowledgement" do
      channel.membership_for(user).destroy!
      expect(pin_action("pinChatMessage").dig("data", "pinChatMessage", "success")).to eq(true)
      expect(pin_action("unpinChatMessage").dig("data", "unpinChatMessage", "success")).to eq(true)
      result = pin_action("markChatPinsRead")
      expect(result.dig("data", "markChatPinsRead", "errors", 0, "code")).to eq("NOT_FOUND")
      expect(channel.membership_for(user)).to be_nil
    end

    it "marks only the actor's pins read and exposes the native membership readback" do
      other = Fabricate(:user)
      other_membership = channel.add(other)
      other_membership.update!(last_viewed_pins_at: 1.day.ago)
      previous = other_membership.last_viewed_pins_at
      freeze_time

      expect(pin_action("markChatPinsRead").dig("data", "markChatPinsRead", "success")).to eq(true)

      membership = channel.membership_for(user)
      expect(membership.last_viewed_pins_at).to eq(Time.zone.now)
      expect(other_membership.reload.last_viewed_pins_at).to eq(previous)
      get "/discourse-graphql/graphql", params: { query: "{ chatChannel(id: #{channel.id.to_s.to_json}) { currentUserMembership { lastViewedPinsAt } } }" }, headers: headers
      expect(response.parsed_body["errors"]).to be_blank
      expect(Time.iso8601(response.parsed_body.dig("data", "chatChannel", "currentUserMembership", "lastViewedPinsAt"))).to eq(membership.last_viewed_pins_at)
    end

    it "retains native closed channel and silenced actor pin behavior" do
      channel.closed!(Discourse.system_user)
      UserSilencer.new(user).silence
      post "/chat/api/channels/#{channel.id}/messages/#{message.id}/pin.json", headers: headers
      expect(response.status).to eq(200)
      delete "/chat/api/channels/#{channel.id}/messages/#{message.id}/pin.json", headers: headers
      expect(response.status).to eq(200)
      expect(pin_action("pinChatMessage").dig("data", "pinChatMessage", "success")).to eq(true)
      expect(pin_action("unpinChatMessage").dig("data", "unpinChatMessage", "success")).to eq(true)
    end

    it "retains native feature NOT_FOUND and disabled Chat sibling execution" do
      SiteSetting.chat_pinned_messages = false
      %w[pinChatMessage unpinChatMessage markChatPinsRead].each do |field|
        result = pin_action(field)
        expect(result.dig("data", field, "errors", 0, "code")).to eq("NOT_FOUND")
      end
      get "/discourse-graphql/graphql", params: { query: "{ capabilities { id available } }" }, headers: headers
      capability = response.parsed_body.dig("data", "capabilities").find { |entry| entry["id"] == "chat.pinControls" }
      expect(capability).to include("available" => false)
      SiteSetting.chat_enabled = false
      result = pin_action("pinChatMessage")
      expect(result.dig("data", "pinChatMessage")).to be_nil
      expect(result.dig("data", "__typename")).to eq("Mutation")
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FEATURE_DISABLED")
    end

    it "denies anonymous controls through the native action lifecycle" do
      %w[pinChatMessage unpinChatMessage markChatPinsRead].each do |field|
        result = pin_action(field, request_headers: {})
        expect(result.dig("data", field, "errors", 0, "code")).to eq("UNAUTHENTICATED")
      end
      expect(Chat::PinnedMessage.where(chat_message: message)).not_to exist
    end

    it "rejects excessive pin controls before publication or persistence" do
      actions = 11.times.map { |index| "a#{index}: pinChatMessage(channelId: #{channel.id.to_s.to_json}, messageId: #{message.id.to_s.to_json}) { success }" }.join(" ")
      publications = MessageBus.track_publish do
        post "/discourse-graphql/graphql", params: { query: "mutation { #{actions} }" }, headers: headers, as: :json
      end
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
      expect(publications).to be_empty
      expect(Chat::PinnedMessage.where(chat_message: message)).not_to exist
    end

    it "retains read credential, GET and readonly protections" do
      query = "mutation { pinChatMessage(channelId: #{channel.id.to_s.to_json}, messageId: #{message.id.to_s.to_json}) { success } }"
      get "/discourse-graphql/graphql", params: { query: query }, headers: headers
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_REQUEST")
      Discourse.enable_readonly_mode
      begin
        pin_action("pinChatMessage", expected_status: 503)
      ensure
        Discourse.disable_readonly_mode
      end
      api_key.update!(scope_mode: :read_only, api_key_scopes: [ApiKeyScope.new(resource: "global", action: "read")])
      pin_action("pinChatMessage", expected_status: 403)
      expect(Chat::PinnedMessage.where(chat_message: message)).not_to exist
    end

    it "requires browser CSRF and accepts the native session token" do
      sign_in(user)
      get "/session/csrf.json"
      token = response.parsed_body.fetch("csrf")
      previous = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      begin
        pin_action("pinChatMessage", request_headers: {}, expected_status: 403)
        expect(Chat::PinnedMessage.where(chat_message: message)).not_to exist
        result = pin_action("pinChatMessage", request_headers: { "X-CSRF-Token" => token, "X-Requested-With" => "XMLHttpRequest" })
        expect(result.dig("data", "pinChatMessage", "success")).to eq(true)
      ensure
        ActionController::Base.allow_forgery_protection = previous
      end
    end
  end

  private

  def pin_action(field, channel_id: channel.id, message_id: message.id, request_headers: headers, expected_status: 200)
    arguments = "channelId: #{channel_id.to_s.to_json}"
    arguments += ", messageId: #{message_id.to_s.to_json}" unless field == "markChatPinsRead"
    post "/discourse-graphql/graphql", params: { query: "mutation { #{field}(#{arguments}) { success errors { code message } } __typename }" }, headers: request_headers, as: :json
    expect(response.status).to eq(expected_status)
    response.parsed_body
  end
end
