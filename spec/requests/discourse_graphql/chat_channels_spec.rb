require "rails_helper"

RSpec.describe DiscourseGraphQL::GraphQLController do
  fab!(:user)
  fab!(:channel, :category_channel)
  fab!(:private_group, :group)
  fab!(:private_channel) { Fabricate(:private_category_channel, group: private_group) }

  let!(:api_key) { Fabricate(:api_key, user: user) }
  let(:headers) { { "Api-Key" => api_key.key, "Api-Username" => user.username } }
  let(:query) do
    <<~GRAPHQL
      query Channels($first: Int, $after: String, $filter: String) {
        chatChannels(first: $first, after: $after, filter: $filter) {
          nodes { id title slug description status threadingEnabled membershipsCount }
          pageInfo { endCursor hasNextPage }
        }
        currentUser { id }
      }
    GRAPHQL
  end

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
  end

  describe "#execute" do
    it "reads the same permitted channel metadata as native discovery" do
      get "/chat/api/channels", headers: headers
      expect(response.status).to eq(200)
      native = response.parsed_body.fetch("channels")

      post "/discourse-graphql/graphql", params: { query: query }, headers: headers

      expect(response.status).to eq(200)
      expect(response.parsed_body["errors"]).to be_blank
      nodes = response.parsed_body.dig("data", "chatChannels", "nodes")
      expect(nodes).to eq(
        native.map do |entry|
          {
            "id" => entry.fetch("id").to_s,
            "title" => entry.fetch("title"),
            "slug" => entry["slug"],
            "description" => entry["description"],
            "status" => entry.fetch("status"),
            "threadingEnabled" => entry.fetch("threading_enabled"),
            "membershipsCount" => entry.fetch("memberships_count"),
          }
        end,
      )
      expect(nodes.map { |entry| entry.fetch("id") }).to eq([channel.id.to_s])
      expect(response.body).not_to include(private_channel.name)
    end

    it "continues a full page to an empty terminal page" do
      post "/discourse-graphql/graphql",
           params: { query: query, variables: { first: 1 } },
           headers: headers,
           as: :json
      cursor = response.parsed_body.dig("data", "chatChannels", "pageInfo", "endCursor")
      expect(cursor).to be_present
      expect(response.parsed_body.dig("data", "chatChannels", "pageInfo", "hasNextPage")).to eq(true)

      post "/discourse-graphql/graphql",
           params: { query: query, variables: { first: 1, after: cursor } },
           headers: headers,
           as: :json

      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.dig("data", "chatChannels")).to eq(
        "nodes" => [],
        "pageInfo" => { "endCursor" => nil, "hasNextPage" => false },
      )
    end

    it "preserves native category name filtering with null defaults" do
      filter = channel.chatable.name
      get "/chat/api/channels", params: { filter: filter }, headers: headers
      expect(response.status).to eq(200)
      native_ids = response.parsed_body.fetch("channels").map { |entry| entry.fetch("id").to_s }
      expect(native_ids).to eq([channel.id.to_s])

      post "/discourse-graphql/graphql",
           params: { query: query, variables: { first: nil, after: nil, filter: filter } },
           headers: headers,
           as: :json

      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.dig("data", "chatChannels", "nodes").map { |entry| entry.fetch("id") }).to eq(native_ids)
      expect(response.parsed_body.dig("data", "chatChannels", "pageInfo")).to eq(
        "endCursor" => nil,
        "hasNextPage" => false,
      )
    end

    it "rejects invalid bounds and changed cursor filters before channel loading" do
      post "/discourse-graphql/graphql",
           params: { query: query, variables: { first: 1 } },
           headers: headers,
           as: :json
      cursor = response.parsed_body.dig("data", "chatChannels", "pageInfo", "endCursor")
      expect(cursor).to be_present

      [
        { first: 0 },
        { first: 51 },
        { after: "invalid" },
        { first: 2, after: cursor },
        { first: 1, after: cursor, filter: channel.name },
      ].each do |variables|
        post "/discourse-graphql/graphql",
             params: { query: query, variables: variables },
             headers: headers,
             as: :json

        expect(response.parsed_body.dig("data", "chatChannels")).to be_nil
        expect(response.parsed_body.dig("data", "currentUser", "id")).to eq(user.id.to_s)
        expect(response.parsed_body.fetch("errors").map { |error| error.dig("extensions", "code") }).to eq(["BAD_USER_INPUT"])
      end
    end

    it "retains native login and group restrictions" do
      get "/discourse-graphql/graphql", params: { query: query }
      expect(response.parsed_body.dig("data", "chatChannels")).to be_nil
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("UNAUTHENTICATED")

      SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:staff]
      post "/discourse-graphql/graphql", params: { query: query }, headers: headers

      expect(response.parsed_body.dig("data", "chatChannels")).to be_nil
      expect(response.parsed_body.dig("data", "currentUser", "id")).to eq(user.id.to_s)
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("FORBIDDEN")
    end

    it "rechecks restricted category membership between requests" do
      private_group.add(user)
      post "/discourse-graphql/graphql", params: { query: query }, headers: headers
      expect(response.parsed_body.dig("data", "chatChannels", "nodes").map { |entry| entry.fetch("id") }).to match_array([channel.id.to_s, private_channel.id.to_s])

      private_group.remove(user)
      post "/discourse-graphql/graphql", params: { query: query }, headers: headers

      expect(response.parsed_body.dig("data", "chatChannels", "nodes").map { |entry| entry.fetch("id") }).to eq([channel.id.to_s])
    end

    it "rejects another actor's cursor and retains current membership on valid continuation" do
      private_group.add(user)
      post "/discourse-graphql/graphql",
           params: { query: query, variables: { first: 1 } },
           headers: headers,
           as: :json
      cursor = response.parsed_body.dig("data", "chatChannels", "pageInfo", "endCursor")
      expect(cursor).to be_present

      other_user = Fabricate(:user)
      other_key = Fabricate(:api_key, user: other_user)
      post "/discourse-graphql/graphql",
           params: { query: query, variables: { first: 1, after: cursor } },
           headers: { "Api-Key" => other_key.key, "Api-Username" => other_user.username },
           as: :json
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("BAD_USER_INPUT")

      private_group.remove(user)
      post "/discourse-graphql/graphql",
           params: { query: query, variables: { first: 1, after: cursor } },
           headers: headers,
           as: :json

      expect(response.parsed_body["errors"]).to be_blank
      expect(response.parsed_body.dig("data", "chatChannels", "nodes")).to eq([])
      expect(response.body).not_to include(private_channel.name)
    end

    it "reports disabled Chat without removing its fields or permitted siblings" do
      SiteSetting.chat_enabled = false
      post "/discourse-graphql/graphql",
           params: { query: "{ capabilities { id available queryFields mutationFields } chatChannels { nodes { id } } currentUser { id } }" },
           headers: headers

      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("data", "chatChannels")).to be_nil
      expect(response.parsed_body.dig("data", "currentUser", "id")).to eq(user.id.to_s)
      expect(response.parsed_body.dig("errors", 0, "extensions", "code")).to eq("FEATURE_DISABLED")
      expect(response.parsed_body.dig("data", "capabilities")).to include(
        "id" => "chat.channelDiscovery",
        "available" => false,
        "queryFields" => ["chatChannels", "chatChannel"],
        "mutationFields" => [],
      )

      SiteSetting.chat_enabled = true
      post "/discourse-graphql/graphql",
           params: { query: "{ capabilities { id available queryFields mutationFields } }" },
           headers: headers
      expect(response.parsed_body.dig("data", "capabilities")).to include(
        "id" => "chat.channelDiscovery",
        "available" => true,
        "queryFields" => ["chatChannels", "chatChannel"],
        "mutationFields" => [],
      )
    end

    it "bounds SQL growth when discovering 50 distinct channels" do
      channels = [channel] + Fabricate.times(49, :category_channel)
      channels.each { |entry| Fabricate(:chat_message, chat_channel: entry) }

      post "/discourse-graphql/graphql", params: { query: query }, headers: headers
      expect(response.parsed_body["errors"]).to be_blank

      query_counts =
        [1, 50].map do |limit|
          queries =
            track_sql_queries do
              post "/discourse-graphql/graphql",
                   params: { query: query, variables: { first: limit } },
                   headers: headers,
                   as: :json
            end
          expect(response.parsed_body["errors"]).to be_blank
          expect(response.parsed_body.dig("data", "chatChannels", "nodes").size).to eq(limit)
          queries.size
        end

      expect(query_counts[1]).to be <= query_counts[0] + 2
    end

    it "preserves native serializer option restrictions" do
      channel.update!(description: "A channel description with enough text")
      plugin = Discourse.plugins_by_name.fetch("discourse-graphql")
      fields = [:id, :title, :slug, :status, :threading_enabled, :memberships_count]
      modifier = ->(options, _guardian) { options.merge(except: [:slug], only: fields) }
      DiscoursePluginRegistry.register_modifier(plugin, :chat_channel_serializer_public_options, &modifier)

      begin
        post "/discourse-graphql/graphql", params: { query: query }, headers: headers

        expect(response.parsed_body["errors"]).to be_blank
        expect(response.parsed_body.dig("data", "chatChannels", "nodes", 0, "description")).to be_nil
        expect(response.parsed_body.dig("data", "chatChannels", "nodes", 0, "slug")).to be_nil
        expect(response.body).not_to include(channel.description)

        fields.delete(:title)
        post "/discourse-graphql/graphql", params: { query: query }, headers: headers

        expect(response.parsed_body.dig("data", "chatChannels")).to be_nil
        expect(response.parsed_body.dig("data", "currentUser", "id")).to eq(user.id.to_s)
        expect(response.parsed_body.fetch("errors").map { |error| error.fetch("path") }).to eq([["chatChannels", "nodes", 0, "title"]])
      ensure
        DiscoursePluginRegistry.unregister_modifier(plugin, :chat_channel_serializer_public_options, &modifier)
      end
    end
  end
end
