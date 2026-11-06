require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController, type: :request do
  it "records native lookup preparation independently of selected thread fields" do
    user = Fabricate(:user, refresh_auto_groups: true)
    channel = Fabricate(:category_channel, threading_enabled: true)
    thread = Fabricate(:chat_thread, channel: channel)
    api_key = Fabricate(:api_key, user: user)
    headers = { "Api-Key" => api_key.key, "Api-Username" => user.username }
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    SiteSetting.max_mentions_per_chat_message = 10
    SiteSetting.enable_user_status = true
    actors = Fabricate.times(50, :user)
    actors.each do |actor|
      Fabricate(:user_chat_mention, chat_message: thread.original_message, user: actor)
    end
    measurements = []
    %w[native graphql_id graphql_mentions].each do |operation|
      records = Hash.new(0)
      listener = ->(_name, _start, _finish, _id, payload) do
        records[payload.fetch(:class_name)] += payload.fetch(:record_count)
      end
      queries = nil
      ActiveSupport::Notifications.subscribed(listener, "instantiation.active_record") do
        queries =
          track_sql_queries do
            if operation == "native"
              get "/chat/api/channels/#{channel.id}/threads/#{thread.id}.json", headers: headers
            else
              selection =
                (
                  if operation == "graphql_id"
                    "id"
                  else
                    "originalMessage { mentionedUsers(first: 50) { nodes { id } totalCount } }"
                  end
                )
              get "/discourse-graphql/graphql",
                  params: {
                    query:
                      "{ chatThread(channelId: \"#{channel.id}\", threadId: \"#{thread.id}\") { #{selection} } }",
                  },
                  headers: headers
            end
          end
      end
      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      if operation == "graphql_id"
        expect(response.parsed_body.dig("data", "chatThread")).to eq("id" => thread.id.to_s)
      elsif operation == "graphql_mentions"
        expect(
          response.parsed_body.dig(
            "data",
            "chatThread",
            "originalMessage",
            "mentionedUsers",
            "nodes",
          ),
        ).to eq(actors.first(10).map { |actor| { "id" => actor.id.to_s } })
      end
      expect(records.fetch("User")).to be >= 50
      measurements << { request: operation, sql_queries: queries.size, loaded_records: records }
    end
    puts JSON.generate(
           measurement: "native_thread_lookup_loading",
           stored_mentions: actors.size,
           native_serialized_limit: 10,
           measurements: measurements,
           unselected_loading_budget_met: false,
         )
  end
end
