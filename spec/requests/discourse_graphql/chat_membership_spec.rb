require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:other_user, :user)
  fab!(:channel, :category_channel)
  fab!(:private_group, :group)
  fab!(:private_channel) { Fabricate(:private_category_channel, group: private_group) }

  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    SiteSetting.direct_message_enabled_groups = Group::AUTO_GROUPS[:everyone]
  end

  after do
    Discourse.disable_readonly_mode
    Discourse.disable_readonly_mode(Discourse::STAFF_WRITES_ONLY_MODE_KEY)
  end

  describe "#execute" do
    it "joins without duplicating membership, sends a message and reads membership state" do
      result =
        graphql(
          query:
            "{ chatChannel(id: \"#{channel.id}\") { id currentUserMembership { following } } }",
        )
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatChannel", "currentUserMembership")).to be_nil

      query =
        "mutation { joinChatChannel(channelId: \"#{channel.id}\") { success membership { channelId following notificationLevel starred } errors { code } } }"
      expect { graphql(query: query) }.to change {
        Chat::UserChatChannelMembership.where(user: user, chat_channel: channel).count
      }.by(1)
      expect(response.parsed_body.dig("data", "joinChatChannel")).to eq(
        "success" => true,
        "membership" => {
          "channelId" => channel.id.to_s,
          "following" => true,
          "notificationLevel" => "MENTION",
          "starred" => false,
        },
        "errors" => [],
      )
      expect { graphql(query: query) }.not_to change(Chat::UserChatChannelMembership, :count)

      result =
        graphql(
          query:
            "mutation { createChatMessage(input: { channelId: \"#{channel.id}\", message: \"A message after joining\" }) { status messageId } }",
        )
      expect(result.dig("data", "createChatMessage", "status")).to eq("CREATED")
      message_id = result.dig("data", "createChatMessage", "messageId")

      result =
        graphql(
          query:
            "{ chatChannel(id: \"#{channel.id}\") { id currentUserMembership { following lastReadMessageId } } }",
        )
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "chatChannel", "currentUserMembership")).to eq(
        "following" => true,
        "lastReadMessageId" => message_id,
      )
    end

    it "keeps stars and notification patches isolated to the current actor" do
      channel.add(user)
      other_membership = channel.add(other_user)
      result =
        graphql(
          query:
            "mutation { starChatChannel(channelId: \"#{channel.id}\", starred: true) { success membership { starred } } updateChatNotifications(input: { channelId: \"#{channel.id}\", muted: true, notificationLevel: ALWAYS }) { success membership { muted notificationLevel } } }",
        )
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "starChatChannel", "membership", "starred")).to eq(true)
      expect(result.dig("data", "updateChatNotifications", "membership")).to eq(
        "muted" => true,
        "notificationLevel" => "ALWAYS",
      )

      result =
        graphql(
          query:
            "mutation { updateChatNotifications(input: { channelId: \"#{channel.id}\", muted: false, notificationLevel: null }) { success membership { muted notificationLevel } } }",
        )
      expect(result.dig("data", "updateChatNotifications", "membership")).to eq(
        "muted" => false,
        "notificationLevel" => "ALWAYS",
      )
      expect(
        other_membership.reload.attributes.slice("starred", "muted", "notification_level"),
      ).to eq("starred" => false, "muted" => false, "notification_level" => "mention")

      result =
        graphql(
          query:
            "mutation { updateChatNotifications(input: { channelId: \"#{channel.id}\" }) { success errors { code } } }",
        )
      expect(result.dig("data", "updateChatNotifications", "success")).to eq(false)
      expect(result.dig("data", "updateChatNotifications", "errors", 0, "code")).to eq(
        "BAD_USER_INPUT",
      )
      expect(channel.membership_for(user).notification_level).to eq("always")
    end

    it "retains private guards and permits native cleanup of stale memberships" do
      private_group.add(user)
      membership = private_channel.add(user)
      message = Fabricate(:chat_message, chat_channel: private_channel)
      GroupUser.where(group: private_group, user: user).delete_all

      [
        "joinChatChannel(channelId: \"#{private_channel.id}\")",
        "starChatChannel(channelId: \"#{private_channel.id}\", starred: true)",
        "updateChatNotifications(input: { channelId: \"#{private_channel.id}\", muted: true })",
        "markChatRead(channelId: \"#{private_channel.id}\", messageId: \"#{message.id}\")",
      ].each do |operation|
        result = graphql(query: "mutation { #{operation} { success errors { code } } }")
        payload = result.fetch("data").values.first
        expect(payload.fetch("success")).to eq(false)
        expect(payload.dig("errors", 0, "code")).to eq("FORBIDDEN")
      end
      expect(membership.reload.starred).to eq(false)
      expect(membership.muted).to eq(false)
      expect(membership.last_read_message_id).to be_nil

      result =
        graphql(
          query:
            "mutation { unfollowChatChannel(channelId: \"#{private_channel.id}\") { success membership { following } } leaveChatChannel(channelId: \"#{private_channel.id}\") { success } }",
        )
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "unfollowChatChannel", "membership", "following")).to eq(false)
      expect(result.dig("data", "leaveChatChannel", "success")).to eq(true)
      expect(membership.reload.following).to eq(false)
    end

    it "retains native group departure and pair conversation unfollow behavior" do
      group_channel =
        Fabricate(:direct_message_channel, users: [user, other_user, Fabricate(:user)])
      pair_channel = Fabricate(:direct_message_channel, users: [user, other_user])

      result =
        graphql(
          query:
            "mutation { unfollowChatChannel(channelId: \"#{group_channel.id}\") { success membership { following } } }",
        )
      expect(result.dig("data", "unfollowChatChannel", "success")).to eq(true)
      expect(group_channel.chatable.users).to include(user)
      expect(group_channel.membership_for(user)).to be_present

      result =
        graphql(
          query:
            "mutation { leaveChatChannel(channelId: \"#{group_channel.id}\") { success membership { following } } leavePair: leaveChatChannel(channelId: \"#{pair_channel.id}\") { success } }",
        )
      expect(result["errors"]).to be_blank
      expect(result.dig("data", "leaveChatChannel", "success")).to eq(true)
      expect(group_channel.membership_for(user)).to be_nil
      expect(group_channel.chatable.users.reload).not_to include(user)
      expect(pair_channel.membership_for(user).following).to eq(false)
      expect(pair_channel.chatable.users).to include(user)

      result = graphql(query: "{ chatChannel(id: \"#{group_channel.id}\") { id } }")
      expect(result.dig("data", "chatChannel")).to be_nil
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FORBIDDEN")
    end

    it "marks only permitted forward reading progress and associated mentions" do
      membership = channel.add(user)
      first, last = Fabricate.times(2, :chat_message, chat_channel: channel)
      notification =
        Notification.create!(
          notification_type: Notification.types[:chat_mention],
          user: user,
          read: false,
          data: {
            message: "chat.mention_notification",
            chat_message_id: first.id,
            chat_channel_id: channel.id,
            mentioned_by_username: first.user.username,
          }.to_json,
        )
      Chat::UserMention.create!(user: user, chat_message: first, notifications: [notification])
      publications =
        MessageBus.track_publish("/chat/user-tracking-state/#{user.id}") do
          graphql(
            query:
              "mutation { markChatRead(channelId: \"#{channel.id}\", messageId: \"#{last.id}\") { success errors { code } } }",
          )
        end

      expect(response.parsed_body.dig("data", "markChatRead", "success")).to eq(true)
      expect(membership.reload.last_read_message_id).to eq(last.id)
      expect(notification.reload.read).to eq(true)
      expect(publications).to include(
        have_attributes(data: include("last_read_message_id" => last.id)),
      )

      result =
        graphql(
          query:
            "mutation { markChatRead(channelId: \"#{channel.id}\", messageId: \"#{first.id}\") { success errors { code } } }",
        )
      expect(result.dig("data", "markChatRead", "errors", 0, "code")).to eq("BAD_USER_INPUT")
      foreign = Fabricate(:chat_message)
      result =
        graphql(
          query:
            "mutation { markChatRead(channelId: \"#{channel.id}\", messageId: \"#{foreign.id}\") { success errors { code } } }",
        )
      expect(result.dig("data", "markChatRead", "errors", 0, "code")).to eq("NOT_FOUND")
      expect(membership.reload.last_read_message_id).to eq(last.id)
    end

    it "marks all native followed memberships while exposing only the update count" do
      other_channel = Fabricate(:category_channel)
      unfollowed = Fabricate(:category_channel)
      memberships =
        [channel, other_channel].map do |entry|
          entry.update!(last_message: Fabricate(:chat_message, chat_channel: entry))
          entry.add(user)
        end
      unfollowed.update!(last_message: Fabricate(:chat_message, chat_channel: unfollowed))
      unfollowed_membership = unfollowed.add(user)
      unfollowed.remove(user)
      other_membership = channel.add(other_user)

      result =
        graphql(
          query:
            "mutation { markAllChatRead { success updatedCount membership { channelId } errors { code } } }",
        )

      expect(result["errors"]).to be_blank
      expect(result.dig("data", "markAllChatRead")).to eq(
        "success" => true,
        "updatedCount" => 2,
        "membership" => nil,
        "errors" => [],
      )
      expect(memberships.map { |membership| membership.reload.last_read_message_id }).to eq(
        [channel.last_message_id, other_channel.last_message_id],
      )
      expect(unfollowed_membership.reload.last_read_message_id).to be_nil
      expect(other_membership.reload.last_read_message_id).to be_nil
    end

    it "keeps native login and absent membership failures" do
      result =
        graphql(
          query:
            "mutation { joinChatChannel(channelId: \"#{channel.id}\") { success errors { code } } }",
          request_headers: {
          },
        )
      expect(result.dig("data", "joinChatChannel", "errors", 0, "code")).to eq("UNAUTHENTICATED")

      result =
        graphql(
          query:
            "mutation { starChatChannel(channelId: \"#{channel.id}\", starred: true) { success errors { code } } }",
        )
      expect(result.dig("data", "starChatChannel", "errors", 0, "code")).to eq("NOT_FOUND")
      expect(channel.membership_for(user)).to be_nil
    end

    it "retains outer readonly and staff writes only protections" do
      query = "mutation { joinChatChannel(channelId: \"#{channel.id}\") { success } }"
      Discourse.enable_readonly_mode
      expect { graphql(query: query) }.not_to change(Chat::UserChatChannelMembership, :count)
      expect(response.status).to eq(503)
      Discourse.disable_readonly_mode

      Discourse.enable_readonly_mode(Discourse::STAFF_WRITES_ONLY_MODE_KEY)
      expect { graphql(query: query) }.not_to change(Chat::UserChatChannelMembership, :count)
      expect(response.status).to eq(503)
      admin = Fabricate(:admin)
      key = Fabricate(:api_key, user: admin)
      result =
        graphql(
          query: query,
          request_headers: {
            "Api-Key" => key.key,
            "Api-Username" => admin.username,
          },
        )
      expect(result.dig("data", "joinChatChannel", "success")).to eq(true)
    end

    it "rejects membership mutations over GET and preserves disabled field siblings" do
      query = "mutation { joinChatChannel(channelId: \"#{channel.id}\") { success } }"
      expect {
        get "/discourse-graphql/graphql", params: { query: query }, headers: headers
      }.not_to change(Chat::UserChatChannelMembership, :count)
      expect(response.status).to eq(400)

      SiteSetting.chat_enabled = false
      result = graphql(query: "{ chatChannel(id: \"#{channel.id}\") { id } currentUser { id } }")
      expect(result.dig("data", "currentUser", "id")).to eq(user.id.to_s)
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FEATURE_DISABLED")
      result =
        graphql(
          query:
            "mutation { joinChatChannel(channelId: \"#{channel.id}\") { success } createPost(input: { topicId: \"0\", raw: \"An unrelated forum reply\" }) { status } }",
        )
      expect(result.dig("data", "joinChatChannel")).to be_nil
      expect(result.dig("data", "createPost", "status")).to eq("FAILED")
      expect(result.dig("errors", 0, "extensions", "code")).to eq("FEATURE_DISABLED")
    end

    it "bounds repeated write work before creating memberships" do
      selections =
        10.times.map do |index|
          "join#{index}: joinChatChannel(channelId: \"#{channel.id}\") { success }"
        end
      expect { graphql(query: "mutation { #{selections.join(" ")} }") }.not_to change(
        Chat::UserChatChannelMembership,
        :count,
      )
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("QUERY_TOO_COMPLEX")
    end

    it "batches selected membership pin metadata across 50 channels" do
      SiteSetting.chat_pinned_messages = true
      channels = [channel] + Fabricate.times(49, :category_channel)
      channels.each do |entry|
        entry.add(user)
        Fabricate(
          :chat_pinned_message,
          chat_channel: entry,
          chat_message: Fabricate(:chat_message, chat_channel: entry),
        )
      end
      unselected =
        track_sql_queries do
          graphql(query: "{ chatChannel(id: \"#{channel.id}\") { id } }")
          graphql(query: "mutation { joinChatChannel(channelId: \"#{channel.id}\") { success } }")
        end
      expect(response.parsed_body["errors"]).to be_blank
      expect(unselected.grep(/FROM\s+\"?chat_pinned_messages\"?/i)).to be_empty
      query =
        "query Pins($limit: Int!) { chatChannels(first: $limit) { nodes { id currentUserMembership { following hasUnseenPins } } } }"
      graphql(query: query, variables: { limit: 1 })

      counts =
        [1, 50].map do |limit|
          queries = track_sql_queries { graphql(query: query, variables: { limit: limit }) }
          expect(response.parsed_body["errors"]).to be_blank
          nodes = response.parsed_body.dig("data", "chatChannels", "nodes")
          expect(nodes.size).to eq(limit)
          expect(nodes.map { |entry| entry.fetch("currentUserMembership") }).to all(
            eq("following" => true, "hasUnseenPins" => true),
          )
          queries.size
        end
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
