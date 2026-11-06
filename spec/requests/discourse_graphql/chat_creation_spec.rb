require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:channel, :category_channel)
  fab!(:private_group, :group)
  fab!(:private_channel) { Fabricate(:private_category_channel, group: private_group) }

  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }
  let(:input) do
    {
      channelId: channel.id,
      message: "A new message from the GraphQL client",
      stagedId: "client-message-1",
    }
  end
  let(:query) { <<~GRAPHQL }
      mutation Create($input: CreateChatMessageInput!) {
        createChatMessage(input: $input) {
          status messageId errors { code message retryAfterSeconds }
        }
      }
    GRAPHQL

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    SiteSetting.direct_message_enabled_groups = Group::AUTO_GROUPS[:everyone]
    channel.add(user)
  end

  describe "#execute" do
    it "persists a message with native publication, events and reading state" do
      publications = nil
      events =
        DiscourseEvent.track_events do
          publications =
            MessageBus.track_publish(Chat::Publisher.root_message_bus_channel(channel.id)) do
              post "/discourse-graphql/graphql",
                   params: {
                     query: query,
                     variables: {
                       input: input,
                     },
                   },
                   headers: headers,
                   as: :json
            end
        end

      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      payload = response.parsed_body.fetch("data").fetch("createChatMessage")
      expect(payload.fetch("status")).to eq("CREATED")
      expect(payload.fetch("errors")).to eq([])
      message = Chat::Message.find(payload.fetch("messageId"))
      expect(message.message).to eq(input.fetch(:message))
      expect(message.user).to eq(user)
      expect(message.chat_channel).to eq(channel)
      expect(channel.reload.last_message_id).to eq(message.id)
      expect(channel.membership_for(user).last_read_message_id).to eq(message.id)
      expect(events.count { |event| event[:event_name] == :chat_message_created }).to eq(1)
      expect(publications).to include(
        have_attributes(
          channel: Chat::Publisher.root_message_bus_channel(channel.id),
          data: include("staged_id" => input.fetch(:stagedId)),
        ),
      )

      get "/chat/api/channels/#{channel.id}/messages", headers: headers
      expect(response.status).to eq(200)
      expect(response.parsed_body.fetch("messages").map { |entry| entry.fetch("id") }).to include(
        message.id,
      )
    end

    it "returns native validation errors without persistence or publication" do
      publications = nil
      expect do
        publications =
          MessageBus.track_publish(Chat::Publisher.root_message_bus_channel(channel.id)) do
            post "/discourse-graphql/graphql",
                 params: {
                   query: query,
                   variables: {
                     input: input.merge(message: ""),
                   },
                 },
                 headers: headers,
                 as: :json
          end
      end.not_to change(Chat::Message, :count)

      payload = response.parsed_body.fetch("data").fetch("createChatMessage")
      expect(payload.fetch("status")).to eq("FAILED")
      expect(payload.fetch("messageId")).to be_nil
      expect(payload.fetch("errors").map { |error| error.fetch("code") }).to all(
        eq("BAD_USER_INPUT"),
      )
      expect(payload.fetch("errors")).to be_present
      expect(publications).to be_empty
    end

    it "retains native login, category and membership restrictions" do
      [nil, headers].each do |request_headers|
        expect do
          post "/discourse-graphql/graphql",
               params: {
                 query: query,
                 variables: {
                   input: input.merge(channelId: private_channel.id),
                 },
               },
               headers: request_headers || {},
               as: :json
        end.not_to change(Chat::Message, :count)

        errors = response.parsed_body.dig("data", "createChatMessage", "errors")
        expect(errors.map { |error| error.fetch("code") }).to eq(
          [request_headers ? "FORBIDDEN" : "UNAUTHENTICATED"],
        )
        expect(response.body).not_to include(private_channel.name)
      end

      channel.membership_for(user).destroy!
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
      end.not_to change(Chat::Message, :count)
      expect(response.parsed_body.dig("data", "createChatMessage", "errors", 0, "code")).to eq(
        "NOT_FOUND",
      )
    end

    it "retains native silencing and closed channel restrictions" do
      channel.update!(status: :closed)
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
      end.not_to change(Chat::Message, :count)
      expect(response.parsed_body.dig("data", "createChatMessage", "errors", 0, "code")).to eq(
        "BAD_USER_INPUT",
      )

      channel.update!(status: :open)
      UserSilencer.new(user).silence
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
      end.not_to change(Chat::Message, :count)
      expect(response.parsed_body.dig("data", "createChatMessage", "errors", 0, "code")).to eq(
        "FORBIDDEN",
      )
    end

    it "keeps threaded replies in their native thread and tracking flow" do
      channel.update!(threading_enabled: true)
      original = Fabricate(:chat_message, chat_channel: channel, user: user)
      channel.update!(last_message: original)

      post "/discourse-graphql/graphql",
           params: {
             query: query,
             variables: {
               input: input.merge(inReplyToId: original.id),
             },
           },
           headers: headers,
           as: :json

      expect(response.parsed_body["errors"]).to be_blank
      payload = response.parsed_body.fetch("data").fetch("createChatMessage")
      expect(payload.fetch("status")).to eq("CREATED")
      reply = Chat::Message.find(payload.fetch("messageId"))
      expect(reply.in_reply_to).to eq(original)
      expect(reply.thread.original_message).to eq(original)
      expect(reply.thread.replies_count_cache).to eq(1)
      expect(reply.thread.membership_for(user).last_read_message_id).to eq(reply.id)
      expect(channel.reload.last_message_id).to eq(original.id)
    end

    it "rejects reply and thread references from another channel" do
      original = Fabricate(:chat_message, chat_channel: private_channel)
      thread = Fabricate(:chat_thread, channel: private_channel, original_message: original)

      [input.merge(inReplyToId: original.id), input.merge(threadId: thread.id)].each do |variables|
        expect do
          post "/discourse-graphql/graphql",
               params: {
                 query: query,
                 variables: {
                   input: variables,
                 },
               },
               headers: headers,
               as: :json
        end.not_to change(Chat::Message, :count)

        expect(response.parsed_body.dig("data", "createChatMessage", "status")).to eq("FAILED")
        expect(response.body).not_to include(original.message, private_channel.name)
      end
    end

    it "shares native rate allowances and automatic silencing" do
      RateLimiter.enable
      SiteSetting.chat_allowed_messages_for_trust_level_0 = 1
      SiteSetting.chat_allowed_messages_for_other_trust_levels = 1
      SiteSetting.chat_auto_silence_duration = 5
      post "/chat/#{channel.id}.json",
           params: {
             message: "The native first message",
           },
           headers: headers
      expect(response.status).to eq(200)

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
      end.not_to change(Chat::Message, :count)

      payload = response.parsed_body.fetch("data").fetch("createChatMessage")
      expect(payload.fetch("status")).to eq("FAILED")
      expect(payload.dig("errors", 0, "code")).to eq("RATE_LIMITED")
      expect(payload.dig("errors", 0, "retryAfterSeconds")).to be > 0
      expect(user.reload).to be_silenced
    end

    it "retains direct message recipient preferences" do
      recipient = Fabricate(:user)
      allowed_user = Fabricate(:user)
      recipient_key = Fabricate(:api_key, user: recipient)
      direct_channel = Fabricate(:direct_message_channel, users: [user, recipient])
      put "/u/#{recipient.username}.json",
          params: {
            enable_allowed_pm_users: true,
            allowed_pm_usernames: allowed_user.username,
          },
          headers: {
            "Api-Key" => recipient_key.key,
            "Api-Username" => recipient.username,
          }
      expect(response.status).to eq(200)

      expect do
        post "/discourse-graphql/graphql",
             params: {
               query: query,
               variables: {
                 input: input.merge(channelId: direct_channel.id),
               },
             },
             headers: headers,
             as: :json
      end.not_to change(Chat::Message, :count)

      payload = response.parsed_body.fetch("data").fetch("createChatMessage")
      expect(payload.fetch("status")).to eq("FAILED")
      expect(payload.dig("errors", 0, "message")).to eq(
        I18n.t("chat.errors.not_accepting_dms", username: recipient.username),
      )
    end

    it "preserves other mutations when Chat is disabled" do
      SiteSetting.chat_enabled = false
      query = <<~GRAPHQL
        mutation {
          createChatMessage(input: { channelId: "#{channel.id}", message: "A disabled message" }) { status }
          createPost(input: { topicId: "0", raw: "An unrelated forum reply" }) { status errors { code } }
        }
      GRAPHQL

      expect do
        post "/discourse-graphql/graphql", params: { query: query }, headers: headers
      end.not_to change(Chat::Message, :count)

      expect(response.parsed_body.dig("data", "createChatMessage")).to be_nil
      expect(response.parsed_body.dig("data", "createPost", "status")).to eq("FAILED")
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("FEATURE_DISABLED")
    end

    it "rejects excessive creation work before any message is persisted or published" do
      operations =
        10.times.map do |index|
          "message#{index}: createChatMessage(input: { channelId: \"#{channel.id}\", message: \"A bounded message #{index}\" }) { status }"
        end
      publications = nil

      expect do
        publications =
          MessageBus.track_publish(Chat::Publisher.root_message_bus_channel(channel.id)) do
            post "/discourse-graphql/graphql",
                 params: {
                   query: "mutation { #{operations.join(" ")} }",
                 },
                 headers: headers
          end
      end.not_to change(Chat::Message, :count)

      expect(
        response.parsed_body.fetch("errors").map { |error| error.dig("extensions", "code") },
      ).to eq(["QUERY_TOO_COMPLEX"])
      expect(publications).to be_empty
    end
  end
end
