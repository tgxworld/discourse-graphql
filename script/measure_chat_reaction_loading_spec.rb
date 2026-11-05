require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController, type: :request do
  it "records native reaction association loading separately from selected serialization" do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    user = Fabricate(:user)
    channel = Fabricate(:category_channel)
    channel.add(user)
    message = Fabricate(:chat_message, chat_channel: channel, user: user)
    actors = Fabricate.times(50, :user)
    actors.each { |actor| Fabricate(:chat_message_reaction, chat_message: message, user: actor, emoji: "heart") }
    api_key = Fabricate(:api_key, user: user)
    headers = { "Api-Key" => api_key.key, "Api-Username" => user.username }
    queries = {
      "graphql_ids" => '{ chatMessages(channelId: "' + channel.id.to_s + '", last: 1) { nodes { id } } }',
      "graphql_reactions" => '{ chatMessages(channelId: "' + channel.id.to_s + '", last: 1) { nodes { id reactions(first: 1) { nodes { emoji count users { id } } } } } }',
    }
    measurements = ["native", *queries.keys].map do |label|
      loaded = Hash.new(0)
      subscriber = ActiveSupport::Notifications.subscribe("instantiation.active_record") do |*arguments|
        payload = arguments.last
        loaded[payload.fetch(:class_name)] += payload.fetch(:record_count)
      end
      begin
        sql = track_sql_queries do
          if label == "native"
            get "/chat/api/channels/#{channel.id}/messages", params: { page_size: 1 }, headers: headers
          else
            post "/discourse-graphql/graphql", params: { query: queries.fetch(label) }, headers: headers, as: :json
          end
        end
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
      expect(response.status).to eq(200)
      result = response.parsed_body
      expect(result["errors"]).to be_blank
      if label == "native"
        expect(result.fetch("messages").map { |entry| entry.fetch("id") }).to eq([message.id])
      else
        node = result.dig("data", "chatMessages", "nodes", 0)
        expect(node.fetch("id")).to eq(message.id.to_s)
        if label == "graphql_ids"
          expect(node.keys).to eq(["id"])
        else
          expect(node.dig("reactions", "nodes", 0, "count")).to eq("50")
          expect(node.dig("reactions", "nodes", 0, "users").size).to eq(5)
        end
      end
      expect(loaded.fetch("Chat::MessageReaction", 0)).to eq(50)
      expect(loaded.fetch("User", 0)).to be >= 50
      { request: label, sql_queries: sql.size, loaded_records: loaded }
    end
    puts JSON.generate(measurement: "native_chat_reaction_loading", reaction_rows: 50, measurements: measurements, unselected_loading_budget_met: false)
  end
end
