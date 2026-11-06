require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user) { Fabricate(:user, name: "Reaction Actor") }
  fab!(:other_user) { Fabricate(:user, name: "Another Reactor") }
  fab!(:channel, :category_channel)
  fab!(:chat_message) { Fabricate(:chat_message, chat_channel: channel, user: user) }
  fab!(:private_group, :group)
  fab!(:private_channel) { Fabricate(:private_category_channel, group: private_group) }
  fab!(:private_message) do
    Fabricate(
      :chat_message,
      chat_channel: private_channel,
      message: "Private reaction content",
      user: user,
    )
  end
  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }
  let(:input) do
    { channelId: channel.id.to_s, messageId: chat_message.id.to_s, emoji: "heart", action: "ADD" }
  end
  let(:mutation) do
    "mutation React($input: ChatReactionChangeInput!) { updateChatReaction(input: $input) { success errors { code message } } }"
  end
  let(:reactors_query) do
    "query Reactors($channel: ID!, $message: ID!, $emoji: String, $first: Int, $after: String) { chatReactionUsers(channelId: $channel, messageId: $message, emoji: $emoji, first: $first, after: $after) { nodes { id username name avatarTemplate reaction } totalCount pageInfo { endCursor hasNextPage } } currentUser { id } }"
  end
  let(:reactors_variables) do
    { channel: channel.id.to_s, message: chat_message.id.to_s, first: 25 }
  end
  let(:summary_query) do
    "query Summary($channel: ID!, $first: Int, $after: String) { chatMessages(channelId: $channel, last: 1) { nodes { id reactions(first: $first, after: $after) { nodes { emoji count reacted users { id username name avatarTemplate } } totalCount pageInfo { endCursor hasNextPage } } } } }"
  end

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    SiteSetting.enable_names = true
    channel.add(user)
  end

  describe "#execute" do
    it "retains native unicode storage, duplicate acknowledgment and repeat publication" do
      publications =
        MessageBus.track_publish(Chat::Publisher.root_message_bus_channel(channel.id)) do
          result = graphql(query: mutation, variables: { input: input.merge(emoji: "👍") })
          expect(result.dig("data", "updateChatReaction", "success")).to eq(true)
          expect(chat_message.reactions.where(user: user).pluck(:emoji)).to eq(["+1"])
          result = graphql(query: mutation, variables: { input: input.merge(emoji: "👍") })
          expect(result.dig("data", "updateChatReaction", "success")).to eq(true)
          expect(chat_message.reactions.where(user: user).count).to eq(1)
          2.times do
            result =
              graphql(
                query: mutation,
                variables: {
                  input: input.merge(emoji: "👍", action: "REMOVE"),
                },
              )
            expect(result.dig("data", "updateChatReaction", "success")).to eq(true)
          end
        end
      expect(chat_message.reactions.where(user: user)).to be_empty
      expect(
        publications.map { |entry| entry.data.slice("type", "action", "emoji", "chat_message_id") },
      ).to eq(
        %w[add add remove remove].map do |action|
          {
            "type" => "reaction",
            "action" => action,
            "emoji" => "+1",
            "chat_message_id" => chat_message.id,
          }
        end,
      )
    end

    it "matches native private thread publication channels, audience and payload" do
      private_group.add(user)
      private_channel.add(user)
      private_channel.update!(threading_enabled: true)
      thread = Fabricate(:chat_thread, channel: private_channel, original_message: private_message)
      reply =
        Fabricate(:chat_message, chat_channel: private_channel, thread_id: thread.id, user: user)
      native_publications =
        MessageBus.track_publish do
          put "/chat/#{private_channel.id}/react/#{reply.id}.json",
              params: {
                emoji: "heart",
                react_action: "add",
              },
              headers: headers
        end
      expect(response.status).to eq(200)
      publications =
        MessageBus.track_publish do
          result =
            graphql(
              query: mutation,
              variables: {
                input: input.merge(channelId: private_channel.id.to_s, messageId: reply.id.to_s),
              },
            )
          expect(result.dig("data", "updateChatReaction", "success")).to eq(true)
        end
      native =
        native_publications.select do |entry|
          entry.data.is_a?(Hash) && entry.data["type"] == "reaction"
        end
      actual =
        publications.select { |entry| entry.data.is_a?(Hash) && entry.data["type"] == "reaction" }
      expect(native).to be_present
      expect(
        actual.map { |entry| [entry.channel, entry.group_ids, entry.user_ids, entry.data] },
      ).to eq(native.map { |entry| [entry.channel, entry.group_ids, entry.user_ids, entry.data] })
      expect(actual.map(&:channel)).to eq(
        [Chat::Publisher.thread_message_bus_channel(private_channel.id, thread.id)],
      )
      expect(reply.reactions.where(user: user, emoji: "heart").count).to eq(1)
    end

    it "preserves absent summaries and reads native sampled groups without popup filtering" do
      result = graphql(query: summary_query, variables: { channel: channel.id })
      expect(result.dig("data", "chatMessages", "nodes", 0, "reactions")).to be_nil
      removed_emoji =
        Fabricate(
          :chat_message_reaction,
          chat_message: chat_message,
          user: user,
          emoji: "removed_custom_emoji_93746",
        )
      result = graphql(query: summary_query, variables: { channel: channel.id })
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatMessages", "nodes", 0, "reactions")).to eq(
        "nodes" => [],
        "totalCount" => 0,
        "pageInfo" => {
          "endCursor" => nil,
          "hasNextPage" => false,
        },
      )
      removed_emoji.destroy!
      [user, other_user].each do |reactor|
        Fabricate(:chat_message_reaction, chat_message: chat_message, user: reactor, emoji: "heart")
      end
      Fabricate(:ignored_user, user: user, ignored_user: other_user)
      get "/chat/api/channels/#{channel.id}/messages", params: { page_size: 1 }, headers: headers
      expect(response.status).to eq(200)
      native =
        response
          .parsed_body
          .fetch("messages")
          .find { |message| message["id"] == chat_message.id }
          .fetch("reactions")
      result = graphql(query: summary_query, variables: { channel: channel.id })
      expect(result["errors"]).to be_blank
      summary = result.dig("data", "chatMessages", "nodes", 0, "reactions")
      expect(summary.fetch("nodes")).to eq(
        native.map do |reaction|
          {
            "emoji" => reaction["emoji"],
            "count" => reaction["count"].to_s,
            "reacted" => reaction["reacted"],
            "users" =>
              reaction
                .fetch("users")
                .map do |actor|
                  {
                    "id" => actor["id"]&.to_s,
                    "username" => actor["username"],
                    "name" => actor["name"],
                    "avatarTemplate" => actor["avatar_template"],
                  }
                end,
          }
        end,
      )
      expect(summary.dig("nodes", 0, "count")).to eq("2")
      result = graphql(query: reactors_query, variables: reactors_variables)
      expect(result.dig("data", "chatReactionUsers", "totalCount")).to eq("1")
      expect(result.dig("data", "chatReactionUsers", "nodes").map { |actor| actor["id"] }).to eq(
        [user.id.to_s],
      )
    end

    it "paginates stored aggregates beyond the mutation limit without truncating groups" do
      emojis = Emoji.all.first(31).map(&:name)
      emojis.each do |emoji|
        Fabricate(:chat_message_reaction, chat_message: chat_message, user: user, emoji: emoji)
      end
      result = graphql(query: summary_query, variables: { channel: channel.id, first: 30 })
      expect(result["errors"]).to be_blank
      first = result.dig("data", "chatMessages", "nodes", 0, "reactions")
      expect(first["totalCount"]).to eq(31)
      expect(first.fetch("nodes").size).to eq(30)
      result =
        graphql(
          query: summary_query,
          variables: {
            channel: channel.id,
            first: 30,
            after: first.dig("pageInfo", "endCursor"),
          },
        )
      expect(result["errors"]).to be_blank
      last = result.dig("data", "chatMessages", "nodes", 0, "reactions")
      expect(
        (first.fetch("nodes") + last.fetch("nodes")).map { |reaction| reaction.fetch("emoji") },
      ).to match_array(emojis)
      expect(last.fetch("pageInfo")).to eq("endCursor" => nil, "hasNextPage" => false)
      result =
        graphql(
          query: summary_query,
          variables: {
            channel: channel.id,
            first: 29,
            after: first.dig("pageInfo", "endCursor"),
          },
        )
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
    end

    it "paginates reaction rows with native ordering and exact stored emoji filters" do
      Fabricate(:chat_message_reaction, chat_message: chat_message, user: user, emoji: "+1")
      Fabricate(
        :chat_message_reaction,
        chat_message: chat_message,
        user: other_user,
        emoji: "heart",
      )
      Fabricate(:chat_message_reaction, chat_message: chat_message, user: user, emoji: "heart")
      get "/chat/#{channel.id}/#{chat_message.id}/reactions-users.json", headers: headers
      expect(response.status).to eq(200)
      native = response.parsed_body
      cursor = nil
      actual = []
      3.times do
        result =
          graphql(
            query: reactors_query,
            variables: reactors_variables.merge(first: 1, after: cursor),
          )
        expect(result["errors"]).to be_blank
        page = result.dig("data", "chatReactionUsers")
        expect(page["totalCount"]).to eq("3")
        actual.concat(page.fetch("nodes"))
        cursor = page.dig("pageInfo", "endCursor")
      end
      expect(cursor).to be_nil
      expect(actual.map { |actor| [actor["id"], actor["reaction"]] }).to eq(
        native.fetch("users").map { |actor| [actor["id"].to_s, actor["reaction"]] },
      )
      result = graphql(query: reactors_query, variables: reactors_variables.merge(emoji: "👍"))
      expect(result.dig("data", "chatReactionUsers", "nodes")).to eq([])
      expect(result.dig("data", "chatReactionUsers", "totalCount")).to eq("0")
      result = graphql(query: reactors_query, variables: reactors_variables.merge(emoji: "+1"))
      expect(result.dig("data", "chatReactionUsers", "nodes").map { |actor| actor["id"] }).to eq(
        [user.id.to_s],
      )
      expect(result.dig("data", "chatReactionUsers", "totalCount")).to eq("1")
      SiteSetting.enable_names = false
      result = graphql(query: reactors_query, variables: reactors_variables)
      expect(result.dig("data", "chatReactionUsers", "nodes").map { |actor| actor["name"] }).to eq(
        [nil, nil, nil],
      )
    end

    it "rejects changed popup cursor context and out of range page sizes" do
      %w[heart +1].each do |emoji|
        Fabricate(:chat_message_reaction, chat_message: chat_message, user: user, emoji: emoji)
      end
      result = graphql(query: reactors_query, variables: reactors_variables.merge(first: 1))
      expect(result["errors"]).to be_blank
      cursor = result.dig("data", "chatReactionUsers", "pageInfo", "endCursor")
      expect(cursor).to be_present
      [
        reactors_variables.merge(first: 2, after: cursor),
        reactors_variables.merge(first: 1, after: cursor, emoji: "heart"),
        reactors_variables.merge(first: 1, after: cursor, message: "0"),
        reactors_variables.merge(first: 1, after: cursor, channel: "0"),
        reactors_variables.merge(after: "invalid"),
        reactors_variables.merge(first: 0),
        reactors_variables.merge(first: 51),
      ].each do |variables|
        result = graphql(query: reactors_query, variables: variables)
        expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      end
    end

    it "rechecks private access after revocation before reads, changes or cursor continuation" do
      private_group.add(user)
      private_channel.add(user)
      %w[heart +1].each do |emoji|
        Fabricate(:chat_message_reaction, chat_message: private_message, user: user, emoji: emoji)
      end
      variables =
        reactors_variables.merge(
          channel: private_channel.id.to_s,
          message: private_message.id.to_s,
          first: 1,
        )
      result = graphql(query: reactors_query, variables: variables)
      expect(result["errors"]).to be_blank
      cursor = result.dig("data", "chatReactionUsers", "pageInfo", "endCursor")
      expect(cursor).to be_present
      private_group.remove(user)
      result = graphql(query: reactors_query, variables: variables.merge(after: cursor))
      expect(result.dig("data", "chatReactionUsers")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FORBIDDEN")
      expect(response.body).not_to include(private_message.message)
      publications =
        MessageBus.track_publish do
          result =
            graphql(
              query: mutation,
              variables: {
                input:
                  input.merge(
                    channelId: private_channel.id.to_s,
                    messageId: private_message.id.to_s,
                    action: "REMOVE",
                  ),
              },
            )
          expect(result.dig("data", "updateChatReaction", "errors", 0, "code")).to eq("FORBIDDEN")
        end
      expect(publications).to be_empty
      expect(private_message.reactions.count).to eq(2)
    end

    it "keeps message scoping and deleted message denial" do
      result =
        graphql(
          query: mutation,
          variables: {
            input: input.merge(messageId: private_message.id.to_s),
          },
        )
      expect(result.dig("data", "updateChatReaction", "errors", 0, "code")).to eq("NOT_FOUND")
      result =
        graphql(
          query: reactors_query,
          variables: reactors_variables.merge(message: private_message.id.to_s),
        )
      expect(result.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
      chat_message.trash!
      result = graphql(query: reactors_query, variables: reactors_variables)
      expect(result.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
      result = graphql(query: mutation, variables: { input: input })
      expect(result.dig("data", "updateChatReaction", "errors", 0, "code")).to eq("NOT_FOUND")
    end

    it "retains following requirements while permitting native removal after unfollow" do
      Fabricate(:chat_message_reaction, chat_message: chat_message, user: user, emoji: "heart")
      Fabricate(
        :chat_message_reaction,
        chat_message: chat_message,
        user: other_user,
        emoji: "heart",
      )
      channel.membership_for(user).update!(following: false)
      result = graphql(query: mutation, variables: { input: input })
      expect(result.dig("data", "updateChatReaction", "errors", 0, "code")).to eq("FORBIDDEN")
      result = graphql(query: mutation, variables: { input: input.merge(action: "REMOVE") })
      expect(result.dig("data", "updateChatReaction", "success")).to eq(true)
      expect(chat_message.reactions.pluck(:user_id)).to eq([other_user.id])
      expect(channel.membership_for(user).following).to eq(false)
    end

    it "retains native channel status, silence and distinct emoji limits" do
      channel.update!(status: :read_only)
      result = graphql(query: mutation, variables: { input: input })
      expect(result.dig("data", "updateChatReaction", "errors", 0, "code")).to eq("FORBIDDEN")
      channel.update!(status: :open)
      emojis = Emoji.all.first(31).map(&:name)
      emojis
        .first(30)
        .each do |emoji|
          Fabricate(:chat_message_reaction, chat_message: chat_message, user: user, emoji: emoji)
        end
      result = graphql(query: mutation, variables: { input: input.merge(emoji: emojis.first) })
      expect(result.dig("data", "updateChatReaction", "success")).to eq(true)
      result = graphql(query: mutation, variables: { input: input.merge(emoji: emojis.last) })
      expect(result.dig("data", "updateChatReaction", "errors", 0, "code")).to eq("FORBIDDEN")
      expect(chat_message.reactions.count).to eq(30)
      UserSilencer.new(user).silence
      result =
        graphql(
          query: mutation,
          variables: {
            input: input.merge(emoji: emojis.first, action: "REMOVE"),
          },
        )
      expect(result.dig("data", "updateChatReaction", "errors", 0, "code")).to eq("FORBIDDEN")
    end

    it "rejects malformed emoji, oversized input and excessive combined work" do
      ["not_a_real_emoji_937461", "x" * 513].each do |emoji|
        result = graphql(query: mutation, variables: { input: input.merge(emoji: emoji) })
        code =
          result.dig("data", "updateChatReaction", "errors", 0, "code") ||
            result.dig("errors", 0, "extensions", "code")
        expect(code).to eq("BAD_USER_INPUT")
      end
      result = graphql(query: mutation, variables: { input: input.merge(action: "DESTROY") })
      expect(result.dig("errors", 0, "extensions", "code")).to eq("GRAPHQL_VALIDATION_FAILED")
      viewed_at = channel.membership_for(user).last_viewed_at
      query =
        "query Expensive($channel: ID!) { chatMessages(channelId: $channel, last: 50) { nodes { reactions(first: 50) { nodes { emoji count reacted users { id username name avatarTemplate } } } } } }"
      result = graphql(query: query, variables: { channel: channel.id })
      expect(result.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
      expect(channel.membership_for(user).reload.last_viewed_at&.to_r).to eq(viewed_at&.to_r)
      selections =
        11
          .times
          .map do |index|
            "reaction#{index}: updateChatReaction(input: { channelId: \"#{channel.id}\", messageId: \"#{chat_message.id}\", emoji: \"heart\", action: ADD }) { success }"
          end
          .join(" ")
      result = graphql(query: "mutation { #{selections} }")
      expect(result.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
      expect(chat_message.reactions).to be_empty
    end

    it "preserves disabled feature roots and native login, GET, readonly and credential guards" do
      result = graphql(query: mutation, variables: { input: input }, request_headers: {})
      expect(result.dig("data", "updateChatReaction", "errors", 0, "code")).to eq("UNAUTHENTICATED")
      get "/discourse-graphql/graphql",
          params: {
            query: mutation,
            variables: { input: input }.to_json,
          },
          headers: headers
      expect(response.status).to eq(400)
      Discourse.enable_readonly_mode
      begin
        graphql(query: mutation, variables: { input: input })
        expect(response.status).to eq(503)
      ensure
        Discourse.disable_readonly_mode
      end
      SiteSetting.site_archived = true
      begin
        graphql(query: mutation, variables: { input: input })
        expect(response.status).to eq(503)
      ensure
        SiteSetting.site_archived = false
      end
      api_key.update!(
        scope_mode: :read_only,
        api_key_scopes: [ApiKeyScope.new(resource: "global", action: "read")],
      )
      graphql(query: mutation, variables: { input: input })
      expect(response.status).to eq(403)
      get "/discourse-graphql/graphql",
          params: {
            query: reactors_query,
            variables: reactors_variables.to_json,
          },
          headers: headers
      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.dig("data", "chatReactionUsers", "totalCount")).to eq("0")
      SiteSetting.chat_enabled = false
      query =
        "query Disabled($channel: ID!, $message: ID!) { chatReactionUsers(channelId: $channel, messageId: $message) { totalCount } currentUser { id } }"
      get "/discourse-graphql/graphql",
          params: {
            query: query,
            variables: { channel: channel.id, message: chat_message.id }.to_json,
          },
          headers: headers
      expect(response.parsed_body.dig("data", "chatReactionUsers")).to be_nil
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("FEATURE_DISABLED")
      expect(response.parsed_body.dig("data", "currentUser", "id")).to eq(user.id.to_s)
      full_key = Fabricate(:api_key, user: user)
      result =
        graphql(
          query:
            "mutation Disabled($input: ChatReactionChangeInput!) { updateChatReaction(input: $input) { success } __typename }",
          variables: {
            input: input,
          },
          request_headers: {
            "Api-Key" => full_key.key,
            "Api-Username" => user.username,
          },
        )
      expect(result.dig("data", "updateChatReaction")).to be_nil
      expect(result.dig("data", "__typename")).to eq("Mutation")
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FEATURE_DISABLED")
      expect(chat_message.reactions).to be_empty
    end

    it "requires browser CSRF verification and accepts the native session header token" do
      sign_in(user)
      get "/session/csrf.json"
      token = response.parsed_body.fetch("csrf")
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      begin
        graphql(query: mutation, variables: { input: input }, request_headers: {})
        expect(response.status).to eq(403)
        expect(chat_message.reactions).to be_empty
        result =
          graphql(
            query: mutation,
            variables: {
              input: input,
            },
            request_headers: {
              "X-CSRF-Token" => token,
              "X-Requested-With" => "XMLHttpRequest",
            },
          )
        expect(result.dig("data", "updateChatReaction", "success")).to eq(true)
        expect(chat_message.reactions.where(user: user, emoji: "heart").count).to eq(1)
      ensure
        ActionController::Base.allow_forgery_protection = original
      end
    end

    it "keeps an unavailable native reaction renderer outside unselected history fields" do
      Chat::MessageSerializer
        .any_instance
        .stubs(:reactions)
        .raises("Reaction rendering unavailable")
      Fabricate(:chat_message_reaction, chat_message: chat_message, user: user, emoji: "heart")
      query =
        "query Read($channel: ID!) { chatMessages(channelId: $channel, last: 1) { nodes { id } } }"
      result = graphql(query: query, variables: { channel: channel.id })
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatMessages", "nodes")).to eq([{ "id" => chat_message.id.to_s }])

      result = graphql(query: summary_query, variables: { channel: channel.id })
      expect(result.dig("data", "chatMessages")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("INTERNAL_ERROR")
    end

    it "retains native only restrictions without recovering omitted attributes from models" do
      Fabricate(:chat_message_reaction, chat_message: chat_message, user: user, emoji: "heart")
      restricted =
        Class.new(Chat::MessageSerializer) do
          def initialize(object, options = {})
            super(object, options.merge(only: [:id]))
          end
        end
      stub_const(Chat, :MessageSerializer, restricted) do
        query =
          "query Read($channel: ID!) { chatMessages(channelId: $channel, last: 1) { nodes { id raw reactions { totalCount } } } }"
        result = graphql(query: query, variables: { channel: channel.id })
        expect(result["errors"]).to be_blank
        expect(result.dig("data", "chatMessages", "nodes")).to eq(
          [{ "id" => chat_message.id.to_s, "raw" => nil, "reactions" => nil }],
        )
      end
    end

    it "binds aggregate continuations to native contents and the current message identity" do
      %w[heart +1].each do |emoji|
        Fabricate(:chat_message_reaction, chat_message: chat_message, user: user, emoji: emoji)
      end
      query =
        "query Partial($channel: ID!, $after: String) { chatMessages(channelId: $channel, last: 1) { nodes { reactions(first: 1, after: $after) { nodes { emoji } pageInfo { endCursor hasNextPage } } } } }"
      result = graphql(query: query, variables: { channel: channel.id })
      cursor = result.dig("data", "chatMessages", "nodes", 0, "reactions", "pageInfo", "endCursor")
      expect(cursor).to be_present
      Fabricate(
        :chat_message_reaction,
        chat_message: chat_message,
        user: other_user,
        emoji: "heart",
      )
      result = graphql(query: query, variables: { channel: channel.id, after: cursor })
      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
      result = graphql(query: query, variables: { channel: channel.id })
      cursor = result.dig("data", "chatMessages", "nodes", 0, "reactions", "pageInfo", "endCursor")
      expect(cursor).to be_present
      replacement = Fabricate(:chat_message, chat_channel: channel, user: user)
      [[user, "heart"], [other_user, "heart"], [user, "+1"]].each do |actor, emoji|
        Fabricate(:chat_message_reaction, chat_message: replacement, user: actor, emoji: emoji)
      end
      get "/chat/api/channels/#{channel.id}/messages", params: { page_size: 2 }, headers: headers
      summaries =
        response.parsed_body.fetch("messages").map { |message| message.fetch("reactions") }
      expect(summaries.size).to eq(2)
      expect(summaries.first).to eq(summaries.last)

      result = graphql(query: query, variables: { channel: channel.id, after: cursor })

      expect(result.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")
    end

    it "supports anonymous native summary paging while retaining reactor and admin restrictions" do
      SiteSetting.chat_allowed_groups =
        "#{Group::AUTO_GROUPS[:everyone]}|#{Group::AUTO_GROUPS[:anonymous_users]}"
      %w[heart +1].each do |emoji|
        Fabricate(:chat_message_reaction, chat_message: chat_message, user: user, emoji: emoji)
      end
      query =
        'query Public($channel: ID!) { chatMessages(channelId: $channel, last: 1) { nodes { reactions(first: 1) { nodes { emoji reacted } pageInfo { endCursor hasNextPage } } } } adminSiteSetting(name: "s3_secret_access_key") { valueWire } }'

      get "/discourse-graphql/graphql",
          params: {
            query: query,
            variables: { channel: channel.id }.to_json,
          }

      result = response.parsed_body
      reaction = result.dig("data", "chatMessages", "nodes", 0, "reactions")
      expect(reaction.fetch("nodes")).to eq([{ "emoji" => "heart", "reacted" => false }])
      expect(reaction.dig("pageInfo", "endCursor")).to be_present
      expect(result.dig("data", "adminSiteSetting")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("NOT_FOUND")
      result = graphql(query: reactors_query, variables: reactors_variables, request_headers: {})
      expect(result.dig("data", "chatReactionUsers")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("UNAUTHENTICATED")
    end

    it "bounds reactor row SQL growth from one to 50 distinct users" do
      actors = Fabricate.times(50, :user)
      actors.each do |actor|
        Fabricate(:chat_message_reaction, chat_message: chat_message, user: actor, emoji: "heart")
      end
      expect(
        graphql(query: reactors_query, variables: reactors_variables.merge(first: 1))["errors"],
      ).to be_blank
      counts =
        [1, 50].map do |first|
          queries =
            track_sql_queries do
              graphql(query: reactors_query, variables: reactors_variables.merge(first: first))
            end
          result = response.parsed_body
          expect(result["errors"]).to be_blank
          expect(
            result.dig("data", "chatReactionUsers", "nodes").map { |actor| actor["id"] },
          ).to eq(actors.first(first).map { |actor| actor.id.to_s })
          expect(result.dig("data", "chatReactionUsers", "totalCount")).to eq("50")
          queries.size
        end
      puts JSON.generate(
             measurement: "chat_reaction_users_sql",
             page_sizes: [1, 50],
             queries: counts,
           )
      expect(counts.last).to be <= counts.first + 2
    end

    it "bounds summary SQL growth for 50 messages with distinct reactors and native samples" do
      messages = [
        chat_message,
        *Fabricate.times(49, :chat_message, chat_channel: channel, user: user),
      ]
      actors = Fabricate.times(50, :user)
      expected = messages.zip(actors).to_h { |message, actor| [message.id.to_s, [actor]] }
      extra_actors = Fabricate.times(5, :user)
      expected.fetch(chat_message.id.to_s).concat(extra_actors)
      messages.each do |message|
        expected
          .fetch(message.id.to_s)
          .each do |actor|
            Fabricate(:chat_message_reaction, chat_message: message, user: actor, emoji: "heart")
          end
      end
      query =
        "query Scale($channel: ID!, $last: Int!) { chatMessages(channelId: $channel, last: $last) { nodes { id reactions(first: 1) { nodes { emoji count reacted users { id username } } } } } }"
      expect(
        graphql(query: query, variables: { channel: channel.id, last: 1 })["errors"],
      ).to be_blank
      counts =
        [1, 50].map do |last|
          queries =
            track_sql_queries do
              graphql(query: query, variables: { channel: channel.id, last: last })
            end
          result = response.parsed_body
          expect(result["errors"]).to be_blank
          nodes = result.dig("data", "chatMessages", "nodes")
          expect(nodes.size).to eq(last)
          nodes.each do |message|
            actors_for_message = expected.fetch(message.fetch("id"))
            reaction = message.dig("reactions", "nodes", 0)
            expect(reaction).to include(
              "emoji" => "heart",
              "count" => actors_for_message.size.to_s,
              "reacted" => false,
            )
            expect(reaction.fetch("users")).to eq(
              actors_for_message
                .first(5)
                .map { |actor| { "id" => actor.id.to_s, "username" => actor.username } },
            )
          end
          queries.size
        end
      puts JSON.generate(
             measurement: "chat_reaction_summaries_sql",
             message_counts: [1, 50],
             queries: counts,
           )
      expect(counts.last).to be <= counts.first + 2
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
