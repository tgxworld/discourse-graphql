require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController, type: :request do
  it "compares native and GraphQL user status query growth for distinct thread actors" do
    user = Fabricate(:user, refresh_auto_groups: true)
    channel = Fabricate(:category_channel, threading_enabled: true)
    channel.add(user)
    api_key = Fabricate(:api_key, user: user)
    headers = { "Api-Key" => api_key.key, "Api-Username" => user.username }
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    SiteSetting.enable_user_status = true
    expected =
      10.times.map do |index|
        actor = Fabricate(:user)
        mentioned = Fabricate(:user)
        actor.set_status!("Working", "computer")
        mentioned.set_status!("Thinking", "bulb")
        thread = Fabricate(:chat_thread, channel: channel, original_message_user: actor)
        reply =
          Fabricate(
            :chat_message,
            chat_channel: channel,
            thread: thread,
            user: actor,
            created_at: (index + 1).minutes.ago,
          )
        thread.update!(last_message: reply, replies_count: 1)
        thread.add(user)
        Fabricate(:user_chat_mention, chat_message: thread.original_message, user: mentioned)
        thread
      end
    measurements = []
    %w[channel current_user].each do |kind|
      %w[native graphql].each do |transport|
        counts =
          [1, 1, 10].map do |first|
              queries =
                track_sql_queries do
                  if transport == "native"
                    path =
                      (
                        if kind == "channel"
                          "/chat/api/channels/#{channel.id}/threads.json"
                        else
                          "/chat/api/me/threads.json"
                        end
                      )
                    get path, params: { limit: first }, headers: headers
                  else
                    field =
                      (
                        if kind == "channel"
                          "chatChannelThreads(channelId: \"#{channel.id}\", first: #{first})"
                        else
                          "currentUserChatThreads(first: #{first})"
                        end
                      )
                    query =
                      "{ #{field} { nodes { id originalMessage { author { id username } mentionedUsers { nodes { id username } } } preview { lastReplyUser { id username } participantUsers { id username } } } } }"
                    get "/discourse-graphql/graphql", params: { query: query }, headers: headers
                  end
                end
              expect(response.status).to eq(200)
              expect(response.parsed_body["errors"]).to be_blank
              nodes =
                (
                  if transport == "native"
                    response.parsed_body.fetch("threads")
                  else
                    response.parsed_body.fetch("data").values.first.fetch("nodes")
                  end
                )
              expect(nodes.map { |entry| entry.fetch("id").to_s }).to eq(
                expected.first(first).map { |entry| entry.id.to_s },
              )
              {
                first: first,
                queries: queries.size,
                user_option_queries: queries.count { |query| query.include?('"user_options"') },
              }
            end
            .drop(1)
        measurements << {
          kind: kind,
          transport: transport,
          measurements: counts,
          growth_budget_met: counts.last.fetch(:queries) <= counts.first.fetch(:queries) + 2,
        }
      end
    end
    puts JSON.generate(
           measurement: "thread_list_status_sql",
           status_enabled: true,
           measurements: measurements,
         )
    expect(
      measurements
        .select { |measurement| measurement.fetch(:transport) == "graphql" }
        .map { |measurement| measurement.fetch(:growth_budget_met) },
    ).to eq([true, true])
  end
end
